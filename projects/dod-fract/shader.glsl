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
#define MOUSE_CONTROL 2

//#define DEBUG

float time;

#define PI 3.14159265359
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
// --------------------------------------------------------

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

// --------------------------------------------------------
// knighty
// https://www.shadertoy.com/view/MsKGzw
// --------------------------------------------------------

struct Tri {
    vec3 a;
    vec3 b;
    vec3 c;
};
    
struct TriPlanes {
    vec3 ab;
    vec3 bc;
    vec3 ca;
};
    
    
vec3 nc,pab,pbc,pca;
Tri triV;
TriPlanes triP;

int Type = 5;

void init() {//setup folding planes and vertex
    float cospin=cos(PI/float(Type)), scospin=sqrt(0.75-cospin*cospin);
    nc=vec3(-0.5,-cospin,scospin);//3rd folding plane. The two others are xz and yz planes
    pab=vec3(0.,0.,1.);
    pbc=vec3(scospin,0.,0.5);//No normalization in order to have 'barycentric' coordinates work evenly
    pca=vec3(0.,scospin,cospin);
    pbc=normalize(pbc); pca=normalize(pca);//for slightly better DE. In reality it's not necesary to apply normalization :) 

    // Triangle vertices
    triV = Tri(pbc, pab, pca);
    // Triangle edge plane normals 
    triP = TriPlanes( 
        normalize(cross(triV.a, triV.b)),
        normalize(cross(triV.b, triV.c)),
        normalize(cross(triV.c, triV.a))
    );
}


void fold(inout vec3 p) {
    for(int i=0;i<5 /*Type*/;i++){
        p.xy = abs(p.xy);
        p -= 2. * min(0., dot(p,nc)) * nc;
    }
}


// Nearest dodecahedron vertex
vec3 dodecahedronVertex(vec3 p) {
    vec3 sp, v1, v2, v3, v4, result, plane;
    sp = sign(p);
    v1 = sp;
    v2 = vec3(0, 1, PHI + 1.) * sp;
    v3 = vec3(1, PHI + 1., 0) * sp;
    v4 = vec3(PHI + 1., 0, 1) * sp;

    plane = vec3(-1. - PHI, -1, PHI) * sp;
    result = mix(v1, v2, max(sign(dot(p, plane)), 0.));
    
    plane = vec3(-1, PHI, -1. - PHI) * sp;
    result = mix(result, v3, max(sign(dot(p, plane)), 0.));
    
    plane = vec3(PHI, -1. - PHI, -1) * sp;
    result = mix(result, v4, max(sign(dot(p, plane)), 0.));
    
    return normalize(result);
}

// --------------------------------------------------------
// Modelling
// --------------------------------------------------------

struct Model {
    float dist;
    float id;
    vec3 uv;
};
    
// checks to see which intersection is closer
Model opU( Model m1, Model m2 ){
    if (m1.dist < m2.dist) {
        return m1;
    } else {
        return m2;
    }
}



float sinstep(float start, float end, float x) {
    float len = end -start;
    x = (x - start) * (1./len);
    x = clamp(x, 0., 1.);
    return sin(x * PI - PI * .5) * .5 + .5;
}

float sinstep(float x) {
    return sinstep(0., 1., x);
}

float sineInOut(float t) {
  return -0.5 * (cos(PI * t) - 1.0);
}

float sineOutIn(float t) {
  return asin(t * 2. - 1.) / PI + .5;
}

float squareSine(float x, float e) {
    x = mod(x, PI * 2.);
    float period = x / mod((PI / 2.), 4.);
    float a = pow(abs(period - 3.), e) - 1.;
    float b = -pow(abs(period - 1.), e) + 1.;
    return period > 2. ? a : b;
}

float squarestep(float start, float end, float x, float e) {
    float len = end -start;
    x = (x - start) * (1./len);
    x = clamp(x, 0., 1.);
    return squareSine(x * PI - PI * .5, e) * .5 + .5;
}

float squarestep(float x, float e) {
    return squarestep(0., 1., x, e);
}

float hardstep(float a, float b, float t) {
    float s = 1. / (b - a);
    return clamp((t - a) * s, 0., 1.);
}



float stepScale = .275;
float stepMove = 2.;
float stepDuration = 2.;
float loopDuration;
float ballSize = 1.;
float stepSpeed = .5;

const float initialStep = 1.;
const float MODEL_STEPS = 3.;


float makeAnim(float localTime) {
    float blend = localTime / stepDuration * stepSpeed;
    blend = clamp(blend, 0., 1.);
    return blend;
}

float moveAnim(float x) {
    float a = 1.;
    float h = 1.;
    float blend = x;
    blend = squarestep(-a, a, blend, 2.) * h * 2. - h;
    blend = squarestep(blend, 1.5);
    return blend;
}

float scaleAnim(float x) {
    return moveAnim(x / stepSpeed);
}

float modelScale;


Model makeModel(vec3 p, float localTime, float scale) {
    float d, part;
    
    float x = makeAnim(localTime);
    float move = moveAnim(x) * stepMove;

    float sizeScale = mix(1., stepScale, scaleAnim(x));
    float size = ballSize * sizeScale;



    p /= scale;
    fold(p);

    vec3 dv = dodecahedronVertex(p);

    part = length(p) - size;
    d = part;

    //d *= scale;
    //return Model(d, 0., vec3(0));

    float r = smoothstep(.05, .5, x) * .4;

    vec3 n = triV.c;
    vec3 pp = p;

    vec3 uv = abs(p) / sizeScale;
    if (length(p) > move * stepMove * .3) {
        pp -= n * move;
        fold(pp);
        uv = abs(pp) / sizeScale;
    }

    
    part = length(p - n * move) - size;
    d = smin(d, part, r);
    
    vec3 rPlane = normalize(cross(triV.b, triV.a));
    n = reflect(n, rPlane);
    part = length(p - n * move) - size;
    d = smin(d, part, r);

    n = reflect(n, triP.ca);
    part = length(p - n * move) - size;
    d = smin(d, part, r);

    // if (d < .1) {
    //     d += (sin((sin(uv.x) + sin(uv.y) + sin(uv.z)) * 8.) * .05) * sizeScale;
    // }

    d *= scale;

    return Model(d, 0., uv * 8.);
}

float makeOffsetMax(float level) {
    float scale = pow(stepScale, level);
    return stepMove * scale;
}

float makeOffsetAmt(float level) {
    float localTime = time - (stepDuration * (level - 1.));
    float x = makeAnim(localTime);
    return moveAnim(x) * makeOffsetMax(level);
}

vec3 makeOffset(float level) {
    return triV.c * makeOffsetAmt(level);
}

float makeSpace(inout vec3 p, float localTime, float scale) {
    float x = makeAnim(localTime);
    float move = moveAnim(x);
    float boundry = 0.;
    
    p /= scale;
    if (length(p) > move * stepMove * .55) {
       fold(p);
       p -= triV.c * move * stepMove;
       boundry = 1.;
    }
    p *= scale;
    return boundry;
}


float makeModelScale() {
    float scale = 1.;
    for (float i = 1. - initialStep; i < MODEL_STEPS; i++) {
        scale *= mix(
            1.,
            stepScale,
            scaleAnim(
                makeAnim(
                    time - (stepDuration * i)
                )
            )
        );
    }
    return (1. / scale);
}

float hash( const in vec3 p ) {
    return fract(sin(dot(p,vec3(127.1,311.7,758.5453123)))*43758.5453123);
}


float timeForStep(float stepIndex, float delay) {
    return time - stepDuration * stepIndex - delay;
}

Model subDModel(vec3 p) {

    float stepIndex = -initialStep;
    float scale = 1.;
    float level = -1.; 
    float localTime = time;
    
    vec3 dv;
    float delay = 0.;
    float stepTime;
    
    float boundry;

    for (float i = 1. - initialStep; i < MODEL_STEPS; i++) {
        dv = dodecahedronVertex(p);
        stepTime = timeForStep(i, delay); 
        if (stepTime > 0.) {
            stepIndex = i;
            stepTime = timeForStep(stepIndex - 1., delay);
            scale = pow(mix(1., stepScale, scaleAnim(stepSpeed)), stepIndex - 1.);
            //scale = 1.;
            boundry = makeSpace(p, stepTime, scale);

            if (boundry > 0.) {
                delay += hash(dv) * 2.;
            }
        }
    }
    /*
    scale = mix(
        pow(stepScale, level + 0.),
        pow(stepScale, level + 1.),
        scaleAnim(makeAnim(localTime - (stepDuration * (level - 1.))))        
    );
    */
   //localTime -= delay;
    //stepIndex -= 0.;
    //stepIndex = 0.;
    stepTime = timeForStep(stepIndex, delay);
    scale = pow(mix(1., stepScale, scaleAnim(stepSpeed)), stepIndex);
    
    return makeModel(p, stepTime, scale);
}

Model map( vec3 p ){
    mat3 m = modelRotation();

    p /= modelScale;

    float x = time / loopDuration;
    x = smoothstep(0., 1., x);
    //x = squarestep(0., .8, x, 2.);
    float blend = 1.-pow(1.-x, 2.);
    vec3 offset = makeOffset(0.);// + makeOffset(1.);
    offset = mix(vec3(0), offset, blend);
    //p += offset;

    Model model = subDModel(p);

    //model = makeModel(p, time, 1.);

    model.dist *= modelScale;
    return model;
}


float camDist;
vec3 camTar;


float newBlendA(float x) {
    float blend;
    blend = sinstep(x / 2. + .5) * 2. - 1.;
    blend = squarestep(blend, 3.);
    return blend;
}

float newBlend(float x) {
    float m = 0.84;
    float o = newBlendA(m);
    return newBlendA(mod(x + m, 1.)) - o + max(sign(x + m - 1.), 0.);
}


void doCamera(out vec3 camPos, out vec3 camTar, out vec3 camUp, in vec2 mouse) {
    float x = time / loopDuration;

    float apex = .6;
    float blend = smoothstep(0., apex, x) - (smoothstep(apex, 1., x));
    blend = sinstep(blend);
    camDist = mix(1.5, 1.7, blend) / stepScale;

    //camDist = 4.5;

    modelScale = makeModelScale();
    float o = .55;
    float sb = squarestep(o, 2. - o, x, 5.) * 2.;
    modelScale = mix(1., modelScale, sb);
    //modelScale = 1.;

    x = mod(x + .5, 1.);

    camUp = vec3(0,-1,0);
    camTar = vec3(0.);
    camPos = vec3(0,0,camDist);
    
    float rotBlend = newBlend(x);
    rotBlend = mix(x, rotBlend, .95);    
    pR(camPos.xz, rotBlend * PI * 2.);

    //camPos = vec3(0,0,camDist);

    camPos *= cameraRotation();
}



// --------------------------------------------------------
// Ray Marching
// Adapted from: https://www.shadertoy.com/view/Xl2XWt
// --------------------------------------------------------

const float MAX_TRACE_DISTANCE = 20.; // max trace distance
const float INTERSECTION_PRECISION = .001; // precision of the intersection
const int NUM_OF_TRACE_STEPS = 100;
const float FUDGE_FACTOR = 1.; // Default is 1, reduce to fix overshoots

struct CastRay {
    vec3 origin;
    vec3 direction;
};

struct Ray {
    vec3 origin;
    vec3 direction;
    float len;
};

struct Hit {
    Ray ray;
    Model model;
    vec3 pos;
    bool isBackground;
    vec3 normal;
    vec3 color;
};

vec3 calcNormal( in vec3 pos ){
    vec3 eps = vec3( 0.001, 0.0, 0.0 );
    vec3 nor = vec3(
        map(pos+eps.xyy).dist - map(pos-eps.xyy).dist,
        map(pos+eps.yxy).dist - map(pos-eps.yxy).dist,
        map(pos+eps.yyx).dist - map(pos-eps.yyx).dist );
    return normalize(nor);
}

Hit raymarch(CastRay castRay){

    float currentDist = INTERSECTION_PRECISION * 2.0;
    Model model;

    Ray ray = Ray(castRay.origin, castRay.direction, 0.);

    for( int i=0; i< NUM_OF_TRACE_STEPS ; i++ ){
        if (currentDist < INTERSECTION_PRECISION || ray.len > MAX_TRACE_DISTANCE) {
            break;
        }
        model = map(ray.origin + ray.direction * ray.len);
        currentDist = model.dist;
        ray.len += currentDist * FUDGE_FACTOR;
    }

    bool isBackground = false;
    vec3 pos = vec3(0);
    vec3 normal = vec3(0);
    vec3 color = vec3(0);

    if (ray.len > MAX_TRACE_DISTANCE) {
        isBackground = true;
    } else {
        pos = ray.origin + ray.direction * ray.len;
        normal = calcNormal(pos);
    }

    return Hit(ray, model, pos, isBackground, normal, color);
}


// --------------------------------------------------------
// Rendering
// --------------------------------------------------------

vec3 camPos;

void shadeSurface(inout Hit hit){

    vec3 background = vec3(.1)* vec3(.5,0,1);

    if (hit.isBackground) {
        hit.color = background;
        return;
    }

    //hit.normal += sin(hit.model.uv * .4) * .4;
    //hit.normal = normalize(hit.normal);

    vec3 light = normalize(vec3(.5,1,0));
    vec3 diffuse = vec3(dot(hit.normal, light) * .5 + .5);
    diffuse = mix(diffuse, vec3(1), .1);
    
    vec3 colA = vec3(.1,.75,.75) * 1.5;
    
    //diffuse *= hit.model.uv;
    diffuse = sin(diffuse);
    diffuse *= 1.3;
    
    float fog = clamp((hit.ray.len - 5.) * .5, 0., 1.);
    fog = mix(0., 1., length(camTar - hit.pos) / pow(camDist, 1.5)) * 1.;
    fog = clamp(fog, 0., 1.);
    
    //*
    diffuse = vec3(.3) * vec3(.9, .3, .8);
    vec3 highlight = vec3(.9) * vec3(.8,.5,1.2);
    float glow = 1. - dot(normalize(camPos), hit.normal);
    glow = squarestep(glow, 2.);
    diffuse = mix(diffuse, highlight, glow);
    diffuse = mix(diffuse, background, fog);
    //*/  
    
    hit.color = diffuse;
    //hit.color = hit.model.uv;
}


vec3 render(Hit hit){

#ifdef DEBUG
    return hit.normal * .5 + .5;
#endif

    shadeSurface(hit);

    return hit.color;
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

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    init();
    
    loopDuration = (MODEL_STEPS + .0) * stepDuration;
    time = iGlobalTime;
    //time += .1;
    time = mod(time, loopDuration);
    //time = loopDuration;
    //time= 0.;
    //time /= 2.;
    //time = mod(time, 1.);

    mousee = iMouse.xy;

    /*
    mousee = (vec2(
        0.4465875370919881,
        0.5849514563106796
    )) * iResolution.xy;
    */

    vec2 p = (-iResolution.xy + 2.0*fragCoord.xy)/iResolution.y;
    vec2 m = mousee.xy / iResolution.xy;

//    time = m.x * loopDuration;

    camPos = vec3( 0., 0., 2.);
    camTar = vec3( 0. , 0. , 0. );
    vec3 camUp = vec3(0., 1., 0.);

    // camera movement
    doCamera(camPos, camTar, camUp, m);

    // camera matrix
    mat3 camMat = calcLookAtMatrix( camPos, camTar, camUp );  // 0.0 is the camera roll

    // create view ray
    vec3 rd = normalize( camMat * vec3(p.xy,2.0) ); // 2.0 is the lens length

    Hit hit = raymarch(CastRay(camPos, rd));

    vec3 color = render(hit);

    #ifndef DEBUG
       color = linearToScreen(color);
    #endif
   // color = linearToScreen(color);
   
    fragColor = vec4(color,1.0);
}
