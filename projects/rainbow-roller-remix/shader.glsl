precision highp float;

uniform vec2 iResolution;
uniform vec2 iOffset;
uniform float iGlobalTime;
uniform vec4 iMouse;
uniform sampler2D iChannel0;


void mainImage(out vec4 a, in vec2 b);

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy + iOffset.xy);
}

#ifdef GL_ES
precision mediump float;
#endif


/* SHADERTOY FROM HERE */


vec2 mousee;

#define MODEL_ROTATION vec2(.5, .5)
#define CAMERA_ROTATION vec2(.5, .5)

// 0: Defaults
// 1: Model
// 2: Camera
#define MOUSE_CONTROL 0

//#define DEBUG

float time;

#define PI 3.14159265359
#define HALF_PI 1.5707963267948966
#define TAU 6.28318530718
#define PHI 1.618033988749895


// --------------------------------------------------------
// Rotation controls
// --------------------------------------------------------

mat3 sphericalMatrix(float theta, float phi) {
    float cx = cos(theta);
    float cy = cos(phi);
    float sx = sin(theta);
    float sy = sin(phi);
    return mat3(
        cy, -sy * -sx, -sy * cx,
        0, cx, sx,
        sy, cy * -sx, cy * cx
    );
}

mat3 mouseRotation(bool enable, vec2 xy) {
    if (enable) {
        vec2 mouse = mousee.xy / iResolution.xy;

        if (mouse.x != 0. && mouse.y != 0.) {
            xy.x = mouse.x;
            xy.y = mouse.y;
        }
    }
    float rx, ry;

    xy.x -= .5;
    //xy *= 2.;

    rx = (xy.y + .5) * PI;
    ry = (-xy.x) * 2. * PI;

    return sphericalMatrix(rx, ry);
}

mat3 modelRotation() {
    mat3 m = mouseRotation(MOUSE_CONTROL==1, MODEL_ROTATION);
    return m;
}

mat3 cameraRotation() {
    mat3 m = mouseRotation(MOUSE_CONTROL==2, CAMERA_ROTATION);
    return m;
}


// --------------------------------------------------------
// HG_SDF
// https://www.shadertoy.com/view/Xs3GRB
// --------------------------------------------------------

#define GDFVector0 vec3(1, 0, 0)
#define GDFVector1 vec3(0, 1, 0)
#define GDFVector2 vec3(0, 0, 1)

#define GDFVector3 normalize(vec3(1, 1, 1 ))
#define GDFVector4 normalize(vec3(-1, 1, 1))
#define GDFVector5 normalize(vec3(1, -1, 1))
#define GDFVector6 normalize(vec3(1, 1, -1))

#define GDFVector7 normalize(vec3(0, 1, PHI+1.))
#define GDFVector8 normalize(vec3(0, -1, PHI+1.))
#define GDFVector9 normalize(vec3(PHI+1., 0, 1))
#define GDFVector10 normalize(vec3(-PHI-1., 0, 1))
#define GDFVector11 normalize(vec3(1, PHI+1., 0))
#define GDFVector12 normalize(vec3(-1, PHI+1., 0))

#define GDFVector13 normalize(vec3(0, PHI, 1))
#define GDFVector14 normalize(vec3(0, -PHI, 1))
#define GDFVector15 normalize(vec3(1, 0, PHI))
#define GDFVector16 normalize(vec3(-1, 0, PHI))
#define GDFVector17 normalize(vec3(PHI, 1, 0))
#define GDFVector18 normalize(vec3(-PHI, 1, 0))

float vmax(vec3 v) {
    return max(max(v.x, v.y), v.z);
}

// Rotate around a coordinate axis (i.e. in a plane perpendicular to that axis) by angle <a>.
// Read like this: R(p.xz, a) rotates "x towards z".
// This is fast if <a> is a compile-time constant and slower (but still practical) if not.
void pR(inout vec2 p, float a) {
    p = cos(a)*p + sin(a)*vec2(p.y, -p.x);
}

float smax(float a, float b, float r) {
    float m = max(a, b);
    if ((-a < r) && (-b < r)) {
        return max(m, -(r - sqrt((r+a)*(r+a) + (r+b)*(r+b))));
    } else {
        return m;
    }
}

float smin(float a, float b, float r) {
    float m = min(a, b);
    if ((a < r) && (b < r) ) {
        return min(m, r - sqrt((r-a)*(r-a) + (r-b)*(r-b)));
    } else {
     return m;
    }
}


// Plane with normal n (n is normalized) at some distance from the origin
float fPlane(vec3 p, vec3 n, float distanceFromOrigin) {
    return dot(p, n) + distanceFromOrigin;
}

// Box: correct distance to corners
float fBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, vec3(0))) + vmax(min(d, vec3(0)));
}

// Cylindrical coordinates
vec3 cartToPolar(vec3 p) {
    float r = length(p.xy); // distance from center
    float z = p.z; // distance from the plane it lies on
    float a = atan(p.y, p.x); // angle around center
    return vec3(r, z, a);
}

float pReflect(inout vec3 p, vec3 planeNormal, float offset) {
    float t = dot(p, planeNormal)+offset;
    if (t < 0.) {
        p = p - (2.*t)*planeNormal;
    }
    return sign(t);
}



// --------------------------------------------------------
// Spectrum colour palette
// IQ https://www.shadertoy.com/view/ll2GD3
// --------------------------------------------------------

vec3 pal( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d ) {
    return a + b*cos( 6.28318*(c*t+d) );
}

vec3 spectrum(float n) {
    return pal( n, vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.0,1.0,1.0),vec3(0.0,0.33,0.67) );
}




// --------------------------------------------------------
// Materials
// --------------------------------------------------------

struct Material {
    vec3 albedo;
    bool specular;
    float transparency;
    float refractiveIndex;
    float reflection;
};


Material ceramicMaterial = Material(
    vec3(.5),
    false,
    0.,
    0.,
    0.
);  
Material waterMaterial = Material(
    vec3(0.),
    true,
    1.,
    // 1. / 1.333,
    // 1. / 1.1,
    1. / 1.01,
    0.
);
Material mirrorMaterial = Material(
    vec3(.7, .3, .0),
    false,
    0.,
    0.,
    1.
);


// --------------------------------------------------------
// Modelling
// --------------------------------------------------------

bool insideTransparency = false;
bool enableTransparency = true;

struct Model {
    float dist;
    Material material;
};

Model newModel() {
    return Model(
        1e12,
        ceramicMaterial
    );
}

// checks to see which intersection is closer
Model opU( Model m1, Model m2 ){
    if (m1.dist < m2.dist) {
        return m1;
    } else {
        return m2;
    }
}



float wave1(vec3 p, vec3 v) {    
    float angle = acos(dot(normalize(p), v));
    float waveA = 0.;
    waveA += cos(angle * 6. * 2.)*4.;
    return waveA;
}


float wave(vec3 p, vec3 v) {    
    return wave1(p, v);
}

Model modelCe(vec3 p) {
    float scale= .8;
    p.z /= scale;
    float d = length(p) - .5;
    p.z -= .3;
    float part = length(p) - .5;
    d = max(d, -part);
    d *= scale;
    return Model(d, waterMaterial);
}

Model modelCx(vec3 p) {
    pReflect(p, vec3(0,0,1), 0.);
    float d = length(p) - .5;
    
    float part = 1e12;
    float s = 1.;
    float a = 1.45;
    part = min(part, length(p - GDFVector13 * a) - s);
    part = min(part, length(p - GDFVector14 * a) - s);
    part = min(part, length(p - GDFVector15 * a) - s);
    part = min(part, length(p - GDFVector16 * a) - s);
    part = min(part, length(p - GDFVector17 * a) - s);
    part = min(part, length(p - GDFVector18 * a) - s);
    d = max(d, -part);
    return Model(d, waterMaterial);
}

Model modelC(vec3 p) {
    Model model = newModel();

    // model.dist = fBox(p, vec3(.5));
    // return model;

    vec3 a = vec3(1,0,0);
    float w = 0.;

    w += wave(p, GDFVector13);
    w += wave(p, GDFVector14);
    w += wave(p, GDFVector15);
    w += wave(p, GDFVector16);
    w += wave(p, GDFVector17);
    w += wave(p, GDFVector18);

    // w += wave(p, GDFVector3);
    // w += wave(p, GDFVector4);
    // w += wave(p, GDFVector5);
    // w += wave(p, GDFVector6);
    // // w += wave(p, GDFVector17);
    // // w += wave(p, GDFVector18);    
    
    float r = w * .005 + .6;
    model.dist = length(p) - r;

    model.dist = mix(model.dist, length(p) - .6, .0);

    // model.dist = fBox(p, vec3(.5));

    return model;
}


Model mainModel(vec3 p) {
    float d = 1e12;
    float part;

    Model model = newModel();
    if ( ! enableTransparency) return model;

    // pR(p.zx, -.5);
    // pR(p.yz, -time);

    model = modelC(p);
    
    if (insideTransparency) model.dist *= -1.;

    model.material = waterMaterial;
    return model;
}

Model map( vec3 p ){
    p *= modelRotation();
    pR(p.yz, time * PI * 2. - .8);
    // pR(camUp.yz, time * PI * 2.);
    Model model;
    model = mainModel(p);
    return model;
}

// --------------------------------------------------------
// Camera
// --------------------------------------------------------

vec3 camPos;
vec3 camTar;
vec3 camUp;


void doCamera() {
    camUp = vec3(0,-1,0);
    camTar = vec3(0.);
    camPos = vec3(0,0,-2.);
    camPos *= cameraRotation();
}


// --------------------------------------------------------
// Camera
// https://www.shadertoy.com/view/Xl2XWt
// --------------------------------------------------------

mat3 calcLookAtMatrix( in vec3 ro, in vec3 ta, in vec3 up )
{
    vec3 ww = normalize( ta - ro );
    vec3 uu = normalize( cross(ww,up));
    vec3 vv = normalize( cross(uu,ww));
    return mat3( uu, vv, ww );
}



// --------------------------------------------------------
// Gamma
// https://www.shadertoy.com/view/Xds3zN
// --------------------------------------------------------

const float GAMMA = 1.;

vec3 gamma(vec3 color, float g) {
    return pow(color, vec3(g));
}

vec3 linearToScreen(vec3 linearRGB) {
    return gamma(linearRGB, 1.0 / GAMMA);
}



const float MAX_TRACE_DISTANCE = 6.; // max trace distance
const float INTERSECTION_PRECISION = .0004; // precision of the intersection
const float FUDGE_FACTOR = .05; // Default is 1, reduce to fix overshoots

const int iter = 105;

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    mousee = iMouse.xy;

    vec2 p = (-iResolution.xy + 2.0*fragCoord.xy)/iResolution.y;
    vec2 m = mousee.xy / iResolution.xy;

    time = iGlobalTime;
    time /= 8.;
    time = mod(time, .5);

    doCamera();

    mat3 camMat = calcLookAtMatrix(camPos, camTar, camUp);
    float focalLength = 2.;
    vec3 rd = normalize(camMat * vec3(p, focalLength));


    vec3 color;
    color = vec3(.25,.5,2)*.005;    

    vec3 ro = camPos;
    float t = 0.0;
    float h = INTERSECTION_PRECISION * 2.0;
    float res = -1.0;
    
    vec3 c;
    
    
    float dist;
    vec3 pos;
    for( int i=0; i < iter; i++ ){
    
        if( t > MAX_TRACE_DISTANCE ) break;
        dist = t;
        Model m = map( ro+rd*t );
        //h = abs(m.dist*max(mix(5., 3., length(ro+rd*t) * 2.), 2.));
        h = abs(m.dist*4.);
        t += max(INTERSECTION_PRECISION, h * FUDGE_FACTOR);
        
        c = vec3(1.4,2.1,1.7) * pow(max(0., (.02 - h)) * 19.5, 10.) * 250.;
        c += vec3(.6,.25,.7) * .05 * FUDGE_FACTOR;

        float ee = smoothstep(MAX_TRACE_DISTANCE, .1, t);
        // if (p.x > 0.) {
            // c *= spectrum(ee* 30. + iGlobalTime * .0);
        // } else {
            c *= spectrum(ee* 300. + iGlobalTime * .0);
        // }
        color += c * ee;
    }

    color = pow(color, vec3(1./1.9)) * 1.2;
    color = pow(color, vec3(1.2));
    
    color *= 2.5;


    fragColor = vec4(color,1.0);
}
