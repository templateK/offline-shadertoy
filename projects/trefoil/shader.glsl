precision highp float;

uniform vec2 iResolution;
uniform vec2 iOffset;
uniform float iTime;
uniform sampler2D iChannel0;

uniform mat4 cameraMatrix;
uniform vec3 cameraPosition;

uniform float guiFocalLength;
uniform float guiSmallRadius;
uniform float guiLargeRadius;
uniform float guiOffsetX;
uniform float guiOffsetY;
uniform float guiOffsetZ;
// uniform float guiRotateX;
// uniform float guiRotateY;
// uniform float guiRotateZ;

void mainImage(out vec4 a, in vec2 b);

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy + iOffset.xy);
}

#ifdef GL_ES
precision mediump float;
#endif


/* SHADERTOY FROM HERE */

// --------------------------------------------------------
// Structs
// --------------------------------------------------------

struct Model {
    float dist;
    vec2 uv;
    int id;
};

struct Hit {
    Model model;
    vec3 pos;
    bool isBackground;
    vec3 normal;
    vec3 rayOrigin;
    vec3 rayDirection;
};


// --------------------------------------------------------
// Utilities
// --------------------------------------------------------

#define PI 3.14159265359
#define TAU 6.28318530718

#define saturate(x) clamp(x, 0., 1.)

void pR(inout vec2 p, float a) {
    p = cos(a)*p + sin(a)*vec2(p.y, -p.x);
}

// Repeat space along one axis
float pMod1(inout float p, float size) {
    float halfsize = size*0.5;
    float c = floor((p + halfsize)/size);
    p = mod(p + halfsize, size) - halfsize;
    return c;
}

// Repeat in three dimensions
vec3 pMod3(inout vec3 p, vec3 size) {
    vec3 c = floor((p + size*0.5)/size);
    p = mod(p + size*0.5, size) - size*0.5;
    return c;
}

float pModPolar(inout vec2 p, float repetitions) {
    float angle = 2.*PI/repetitions;
    float a = atan(p.y, p.x) + angle/2.;
    float r = length(p);
    float c = floor(a/angle);
    a = mod(a,angle) - angle/2.;
    p = vec2(cos(a), sin(a))*r;
    // For an odd number of repetitions, fix cell index of the cell in -x direction
    // (cell index would be e.g. -5 and 5 in the two halves of the cell):
    if (abs(c) >= (repetitions/2.)) c = abs(c);
    return c;
}

// Distance to line segment between <a> and <b>, used for fCapsule() version 2below
float fLineSegment(vec3 p, vec3 a, vec3 b) {
    vec3 ab = b - a;
    float t = saturate(dot(p - a, ab) / dot(ab, ab));
    return length((ab*t + a) - p);
}

// Capsule version 2: between two end points <a> and <b> with radius r 
float fCapsule(vec3 p, vec3 a, vec3 b, float r) {
    return fLineSegment(p, a, b) - r;
}

// A circular disc with no thickness (i.e. a cylinder with no height).
float fDisc(vec3 p, float r) {
 float l = length(p.xz) - r;
    return l < 0. ? abs(p.y) : length(vec2(p.y, l));
}

float vmax(vec2 v) {
    return max(v.x, v.y);
}

float vmax(vec3 v) {
    return max(max(v.x, v.y), v.z);
}

float range(float vmin, float vmax, float value) {
  return (value - vmin) / (vmax - vmin);
}

float rangec(float a, float b, float t) {
    return clamp(range(a, b, t), 0., 1.);
}

float fBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, vec3(0))) + vmax(min(d, vec3(0)));
}


float fBox2(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, vec2(0))) + vmax(min(d, vec2(0)));
}

vec3 intersectPlane(vec3 rayOrigin, vec3 rayDirection, vec3 normal, float offset) {
    float dist = dot(normal, normal * offset - rayOrigin) / dot(normal, rayDirection);
    return rayOrigin + rayDirection * dist;
}

// Cartesian to polar coordinates
vec3 cartToPolar(vec3 p) {
    float x = p.x; // distance from the plane it lies on
    float a = atan(p.y, p.z); // angle around center
    float r = length(p.zy); // distance from center
    return vec3(x, a, r);
}

// Polar to cartesian coordinates
vec3 polarToCart(vec3 p) {
    return vec3(
        p.x,
        sin(p.y) * p.z,
        cos(p.y) * p.z
    );
}

vec2 closestPointOnLine(vec2 line, vec2 point){
    line = normalize(line);
    float d = dot(point, line);
    return line * d;
}

// Closest of two points
vec3 closestPoint(vec3 pos, vec3 p1, vec3 p2) {
    if (length(pos - p1) < length(pos - p2)) {
        return p1;
    } else {
        return p2;
    }
}

// http://www.neilmendoza.com/glsl-rotation-about-an-arbitrary-axis/
mat3 rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

vec3 bezierTangent(vec3 A, vec3 B, vec3 C, float t) {
    return 2. * (1. - t) * (B - A) + 2. * t * (C - B);
}

vec4 sdBezier(vec3 A, vec3 B, vec3 C, vec3 pos)
{    
    vec3 a = B - A;
    vec3 b = A - 2.0*B + C;
    vec3 c = a * 2.0;
    vec3 d = A - pos;

    float kk = 1.0 / dot(b,b);
    float kx = kk * dot(a,b);
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);      

    vec4 res;

    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
    float h = q*q + 4.0*p3;

    if(h >= 0.0) 
    { 
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x)*pow(abs(x), vec2(1.0/3.0));
        float t = uv.x + uv.y - kx;
        t = clamp( t, 0.0, 1.0 );

        // 1 root
        vec3 qos = A + (c + b*t)*t;
        res = vec4(qos, t);
    }
    else
    {
        float z = sqrt(-p);
        float v = acos( q/(p*z*2.0) ) / 3.0;
        float m = cos(v);
        float n = sin(v)*1.732050808;
        vec3 t = vec3(m + m, -n - m, n - m) * z - kx;
        t = clamp( t, 0.0, 1.0 );

        // 3 roots
        vec3 qos = A + (c + b * t.x) * t.x;
        float dis = dot(qos - pos, qos);
        res = vec4(qos, t.x);

        qos = A + (c + b * t.y) * t.y;
        float dis2 = dot(qos - pos, qos);
        if( dis2 < dis ) {
            res = vec4(qos, t.y);
            dis = dis2;
        }

        qos = A + (c + b * t.z) * t.z;
        dis2 = dot(qos - pos,qos);
        if (dis2 < dis) {
            res = vec4(qos, t.z);
        }
    }
    
    return res;
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
// Helix
// --------------------------------------------------------

vec2 closestPointOnRepeatedLine(vec2 line, vec2 point){

    // Angle of the line
    float a = atan(line.x, line.y);

    // Rotate space so we can easily repeat along
    // one dimension
    pR(point, -a);

    // Repeat to create parallel lines at the corners
    // of the vec2(lead, radius) polar bounding area
    float repeatSize = (sin(a) * line.y) / 2.;
    float cell = pMod1(point.x, repeatSize);

    // Rotate space back to where it was
    pR(point, a);

    // Closest point on a line
    line = normalize(line);
    float d = dot(point, line);
    vec2 closest = line * d;

    // Part 2 of the repeat, move the line along it's
    // perpendicular by the repeat cell
    vec2 perpendicular = vec2(line.y, -line.x);
    closest += cell * repeatSize * perpendicular;

    return closest;
}

// Closest point on a helix
vec3 closestHelix(vec3 p, float lead, float radius) {

    p = cartToPolar(p);
    p.y *= radius;

    vec2 line = vec2(lead, radius * PI * 2.);
    vec2 closest = closestPointOnRepeatedLine(line, p.xy);

    closest.y /= radius;
    vec3 closestCart = polarToCart(vec3(closest, radius));

    return closestCart;
}

// Cartesian to helix coordinates
void pModHelix(inout vec3 p, float lead, float radius) {
    vec3 closest = closestHelix(p, lead, radius);
    float helixAngle = atan((2. * PI * radius) / lead);
    vec3 normal = normalize(closest - vec3(closest.x,0,0));
    vec3 tangent = vec3(1,0,0) * rotationMatrix(normal, helixAngle);
    float x = (closest.x / lead) * radius * PI * 2.;
    float y = dot(p - closest, cross(tangent, normal));
    float z = dot(p - closest, normal);
    p = vec3(x, y, z);
}

float pModHelixScale(inout vec3 p, float lead, float innerRatio) {
    float radius = mix(.25, .5, innerRatio);
    pModHelix(p, lead, radius);
    float scale = mix(.5, 0., innerRatio);
    p /= scale;
    return 1. / scale;
}

vec3 knot(float a)
{
    // http://en.wikipedia.org/wiki/Trefoil_knot
    return vec3(
        sin(a) + 2. * sin(2. * a),
        cos(a) - 2. * cos(2. * a),
        -sin(3. * a)
    ) / 3.;
}

float fTrefoil(vec3 p) {
    // p = p.zxy * -1.;
    // return length(p) - 1.;
    float d = 1e12;
    const int steps = 40;
    float radius = .03;
    float ratio = 1.;
    for (int i = 0; i < steps; i++) {
        float a = float(i) * (PI * 2.) / float(steps);
        vec3 b = ratio * knot(a + iTime * .1);
        d = min(d, length(p - b) - radius);
    }
    return d;
}

// Torus in the XZ-plane
float fTorus(vec3 p, float smallRadius, float largeRadius) {
    return length(vec2(length(p.xz) - largeRadius, p.y)) - smallRadius;
}

float fShape(vec3 p) {
    float d;
    p = p.yzx;
    p = cartToPolar(p);
    p.z -= .5;
    
    p = p.yxz;
    // p.x += iTime;
    pModHelix(p, PI * 4./3., .25);
    d = length(p.yz) - .125 / 4.;
    // d = fBox2(p.yz, vec2(.25));
    return d;
}

vec4 unionBezier(vec3 p, vec4 a, vec4 b) {
    if (length(p - a.xyz) < length(p - b.xyz)) {
        return a;
    }
    return b;
}

float switchBezier(vec3 p, vec4 a, vec4 b) {
    return length(p - a.xyz) - length(p - b.xyz);
}

struct Curve {
    vec3 position;
    vec3 tangent;
    vec3 normal;
    vec3 binormal;
    float t;
};

struct CurvePart {
    vec4 bez;
    vec3 tangent;
    vec3 normal;
    float offset;
};

// 14
vec3 a0 = vec3(-0.5646339746784572, -0.24718472957582266, 0.3203066290885463);
vec3 b0 = vec3(-0.2179807626050522, -0.4117461734207104, 0.28192340787643694);
vec3 c0 = vec3(0, -0.4117461734207104, 0);
vec3 aTan0 = vec3(0.9004293690011601, -0.39066687906038094, -0.1913278365669635);
vec3 cTan0 = vec3(0.6119952767883093, 0.0002637554238998603, -0.7908613732013197);
vec3 aNor0 = vec3(-0.31066154543681135, -0.8853858853973771, 0.34580520257207714);
vec3 cNor0 = vec3(0.00016141707926865776, -0.9999999652165374, -0.00020859398399036068);
// 0
vec3 a1 = vec3(0, -0.4117461734207104, 0);
vec3 b1 = vec3(0.2179807626050522, -0.4117461734207104, -0.28192340787643694);
vec3 c1 = vec3(0.5646339746784572, -0.24718472957582266, -0.3203066290885463);
vec3 aTan1 = vec3(0.6119952767883093, 0.0002637554238998603, -0.7908613732013197);
vec3 cTan1 = vec3(0.9004293690011631, 0.3906668790603784, -0.19132783656695382);
vec3 aNor1 = vec3(0.00016141707926865776, -0.9999999652165374, -0.00020859398399036068);
vec3 cNor1 = vec3(0.3106615610386103, -0.8853858983061528, -0.34580515550474455);
// 1
vec3 a2 = vec3(0.5646339746784572, -0.24718472957582266, -0.3203066290885463);
vec3 b2 = vec3(0.9112871867518623, -0.08262328573093487, -0.35868985030065564);
vec3 c2 = vec3(0.9385208926061067, 0.23747769583063397, -0.17934492515032782);
vec3 aTan2 = vec3(0.9004293690011631, 0.3906668790603784, -0.19132783656695382);
vec3 cTan2 = vec3(0.1363483693034041, 0.874428117557939, 0.4656013202433836);
vec3 aNor2 = vec3(0.3106615610386103, -0.8853858983061528, -0.34580515550474455);
vec3 cNor2 = vec3(0.9663147996664277, -0.013837886557081045, -0.25699070185760564);
// 6
vec3 a3 = vec3(-0.5054950226046985, -0.36882329304593764, -0.3203066290885463);
vec3 b3 = vec3(-0.532368539142374, -0.7552219452779392, -0.35868985030065564);
vec3 c3 = vec3(-0.2661842695711869, -0.9479661894438923, -0.17934492515032782);
vec3 aTan3 = vec3(-0.10477538648781647, -0.976009893331736, -0.19085807948552239);
vec3 cTan3 = vec3(0.6836058218327101, -0.5691582989230419, 0.4568828199040257);
vec3 aNor3 = vec3(-0.9254780853973159, 0.16593937919080945, -0.34052083032185704);
vec3 cNor3 = vec3(-0.5072230922675671, -0.8205991490310933, -0.26332825765567275);
// 7
vec3 a4 = vec3(-0.2661842695711869, -0.9479661894438923, -0.17934492515032782);
vec3 b4 = vec3(1.396967381274287e-16, -1.1407104336098457, 0);
vec3 c4 = vec3(0.26618426957118707, -0.9479661894438923, 0.17934492515032782);
vec3 aTan4 = vec3(0.6836058218327101, -0.5691582989230419, 0.4568828199040257);
vec3 cTan4 = vec3(0.6836058218326713, 0.569158298923105, 0.4568828199040053);
vec3 aNor4 = vec3(-0.5072230922675671, -0.8205991490310933, -0.26332825765567275);
vec3 cNor4 = vec3(0.5072230653779741, -0.8205991516815608, 0.2633283011908782);

CurvePart bezierInner(vec3 p) {
    vec4 bez, bezPart;
    vec3 a, b, c,
        aTan, cTan, aNor, cNor,
        tan, nor;
    float offset;

    a = a0;
    b = b0;
    c = c0;
    aTan = aTan0;
    cTan = cTan0;
    aNor = aNor0;
    cNor = cNor0;
    bezPart = sdBezier(a, b, c, p);
    bez = bezPart;
    tan = mix(aTan, cTan, bez.w);
    nor = mix(aNor, cNor, bez.w);
    offset = 0.;

    a = a1;
    b = b1;
    c = c1;
    aTan = aTan1;
    cTan = cTan1;
    aNor = aNor1;
    cNor = cNor1;
    bezPart = sdBezier(a, b, c, p);
    if (switchBezier(p, bez, bezPart) > 0.) {
        bez = bezPart;
        tan = mix(aTan, cTan, bez.w);
        nor = mix(aNor, cNor, bez.w);
        offset = 1.;
    }

    a = a2;
    b = b2;
    c = c2;
    aTan = aTan2;
    cTan = cTan2;
    aNor = aNor2;
    cNor = cNor2;
    bezPart = sdBezier(a, b, c, p);
    if (switchBezier(p, bez, bezPart) > 0.) {
        bez = bezPart;
        tan = mix(aTan, cTan, bez.w);
        nor = mix(aNor, cNor, bez.w);
        offset = 2.;
    }

    return CurvePart(
        bez,
        tan,
        nor,
        offset
    );
}

CurvePart bezierOuter(vec3 p) {
    vec4 bez, bezPart;
    vec3 a, b, c,
        aTan, cTan, aNor, cNor,
        tan, nor;
    float offset;

    a = a3;
    b = b3;
    c = c3;
    aTan = aTan3;
    cTan = cTan3;
    aNor = aNor3;
    cNor = cNor3;
    bezPart = sdBezier(a, b, c, p);
    bez = bezPart;
    tan = mix(aTan, cTan, bez.w);
    nor = mix(aNor, cNor, bez.w);
    offset = 0.;

    a = a4;
    b = b4;
    c = c4;
    aTan = aTan4;
    cTan = cTan4;
    aNor = aNor4;
    cNor = cNor4;
    bezPart = sdBezier(a, b, c, p);
    if (switchBezier(p, bez, bezPart) > 0.) {
        bez = bezPart;
        tan = mix(aTan, cTan, bez.w);
        nor = mix(aNor, cNor, bez.w);
        offset = 1.;
    }

    return CurvePart(
        bez,
        tan,
        nor,
        offset
    );
}

Curve TrefoilCurve(vec3 p) {

    vec4 bez, bezPart;
    
    float side = 0.;
    float tFlip = 1.;

    float cell = 0.;

    float repetitions = 3.;
    float angle = TAU / repetitions;


    if (p.z > 0.) {
        p.z *= -1.;
        p.y *= -1.;
        pR(p.xy, angle / -2.);
        side = 1.;
        tFlip = -1.;
    }
    pR(p.xy, angle / -2.);
    cell = pModPolar(p.xy, repetitions);
    pR(p.xy, angle / 2.);


    float outer = 0.;

    CurvePart curve = bezierInner(p);
    CurvePart outerCurve = bezierOuter(p);

    if (switchBezier(p, curve.bez, outerCurve.bez) > 0.) {
        outer = 1.;
        curve = outerCurve;
    }

    // float flip = sign(p.z);
    // side = flip * .5 + .5;

    // float rot = side * TAU / -6.;
    // rot = 0.;

    // vec3 pp = p;
    // cell = floor((atan(p.y, p.x) + angle / 2. - rot) / angle);

    float an = cell * angle;

    mat3 m = mat3(
        cos(an), -sin(an), 0,
        sin(an), cos(an), 0,
        0, 0, 1
    );

    mat3 m2 = mat3(
        cos(angle / -2.), -sin(angle / -2.), 0,
        sin(angle / -2.), cos(angle / -2.), 0,
        0,0,-1
    );
    mat3 m3 = mat3(1,0,0,0,-1,0,0,0,1);

    if (side > 0.) {
        m = m * m2 * m3;
    }

    // m = mat3(1,0,0,0,1,0,0,0,1);


    float parts = 24.;

    float sectionCurveOffset;

    vec3 tangent = curve.tangent;
    vec3 normal = curve.normal;
    vec3 binormal = cross(tangent, normal);

    normal *= -1.;

    if (side > 0.) {
        binormal *= -1.;
    }

    tangent = normalize(tangent);
    binormal = normalize(binormal);
    normal = normalize(normal);

    vec3 plane;
    float dp;
    
    float part;

    // part = 2. * side;
    // part += cell * (1. - side * 2.);
    // part *= 4.;
    // part *= 1. + 1. * outer;
    // part += 5. * outer;
    // part += side;
    // part *= -1. + outer * 2.;
    // part = mod(part, 12.);

    float t= 0.;

    // if (hlf == 0.) {
    //     t = bez.w * .5;
    // } else {
    //     t = .5 + bez.w * .5;
    // }

    if (side > 0.) {
        t = 1. - t;
    }
    // t = 0.;

    // t += part / 12.;

    // we want curve index
    // each curve has an index offset
        // where 0 is the first curve
        // entering the cell
        // curves before entering get -1
    // find starting index from 
        // inner / outer
        // side
        // cell
        // outer curve parts in cell
        // inner curve parts in cell

    float innerParts = 1.;
    float outerParts = 2.;
    float innerOffset;
    float outerOffset;

    cell = mod(cell, 3.);

    if (side == 0.) {
        if (cell == 0.) {
            innerOffset = 0.;
            outerOffset = 7.;
        }
        if (cell == 1.) {
            innerOffset = 10.;
            outerOffset = 2.;
        }
        if (cell == 2.) {
            innerOffset = 5.;
            outerOffset = 12.;
        }
    }
    if (side == 1.) {
        if (cell == 0.) {
            innerOffset = 6.;
            outerOffset = 14.;
        }
        if (cell == 1.) {
            innerOffset = 11.;
            outerOffset = 4.;
        }
        if (cell == 2.) {
            innerOffset = 1.;
            outerOffset = 9.;
        }
    }

    float offset;

    if (outer == 1.) {
        offset = outerOffset;
    } else {
        offset = innerOffset;
    }

    if (side > 0.) {
        t = (1. + offset - curve.bez.w - curve.offset) / 15.;
    } else {
        t = (offset + curve.bez.w + curve.offset) / 15.;
    }


    vec3 position = curve.bez.xyz;

    return Curve(
        position * m,
        curve.tangent * m,
        normal * m,
        binormal * m,
        t
    );
}

vec2 fShape2(vec3 p) {
    float d = 1e12;

    float s = 1.;


    // if (length(p) > 2.) {
    //     s = dot(p,p);
    //     s /= 3.;
    //     pR(p.xy, PI * .5);
    // }

    p /= s;
    vec3 pp = p;

    Curve curve = TrefoilCurve(p);

    d = min(d, length(p - curve.position) - .2);

    // d = min(d, fCapsule(p, bez.xyz, bez.xyz + tangent * .5, .005));
    // d = min(d, fCapsule(p, curve.position, curve.position + curve.binormal * .25, .005));
    // d = min(d, fCapsule(p, curve.position, curve.position + curve.normal * .5, .005));

    float x = curve.t;
    float y = dot(p - curve.position, curve.normal);
    float z = dot(p - curve.position, curve.binormal);
    p = vec3(x, y, z);

    // d = length(p.yz) - .2;

    // p.x += iTime * .1;
    // pMod1(p.x, 1./2.5);
    // d = fBox(p, vec3(.15,.33,.33));

    // pR(p.yz, iTime * .5);
    // pR(p.yz, p.x * PI * 2. * -5.);
    // d = fBox2(p.yz, vec2(.3));

    // d = min(d, length(p - vec3(0,0,1)) - .2);

    p = pp;

    // vec3 plane;
    // float dp;

    // plane = vec3(0,0,1);
    // dp = abs(dot(p, plane)) - .001;
    // dp = max(dp, length(p) - 1.);
    // d = min(d, dp);

    // // // d = min(d, length(p - b) - .03);
    
    // pR(p.xy, TAU / 3.);
    // // pR(p.xy, TAU / 6.);
    // pModPolar(p.xy, 3.);
    // plane = vec3(0,1,0);
    // dp = abs(dot(p, plane)) - .001;
    // dp = max(dp, length(p) - 1.);
    // d = min(d, dp);


    d *= s;

    return vec2(d, curve.t);
}

float focalLength;

Model map(vec3 p) {
    float d;
    float s = focalLength;
    p *= s;

    // p += vec3(guiOffsetX, guiOffsetY, guiOffsetZ) * 3.;

    d = fTorus(p, guiSmallRadius, guiLargeRadius);
    
    vec2 duv = fShape2(p);

    d = duv.x;
    // d = min(d, fShape(p));
    // d = min(d, fTrefoil(p));
    // d = min(d, length(p) - 1.);
    // d = abs(d) - .001;

    d /= s;

    return Model(d, duv.yy, 0);
}


// --------------------------------------------------------
// Rendering
// --------------------------------------------------------

vec3 camPos;

vec3 render(Hit hit){
    vec3 col;
    vec3 bg = vec3(.9,.3, .9) * .02;
    col = bg;
    if ( ! hit.isBackground) {
        vec2 uv = hit.model.uv;
        // uv *= vec2(4., 8.);
        // uv = cos(uv * PI * 2.);
        // uv = smoothstep(.5, .55, uv);
        col = spectrum(uv.x);

        vec3 light = normalize(vec3(.5,1,0));
        vec3 diffuse = vec3(dot(hit.normal, light) * .5 + .5);
        col *= diffuse;
        vec3 ref = reflect(hit.rayDirection, hit.normal);
        // col = normalize(hit.normal) * .5 + .5;
        // col = vec3(col.b);
        // col = mix(col, bg, clamp(0., 1., smoothstep(length(camPos * .25), length(camPos * 2.5), length(camPos - hit.pos))));
    }
    // if (hit.isBackground || hit.pos.z > 0.) {
    //     vec3 debugPlanePos = intersectPlane(
    //         hit.rayOrigin, hit.rayDirection, vec3(0,0,1), 0.
    //     );
    //     float dist = map(debugPlanePos).dist;
    //     vec3 meter = vec3(mod(dist, 1./4.));
    //     col = mix(col, meter, .5);
    // }
    return col;
}


// --------------------------------------------------------
// Ray Marching
// Adapted from: https://www.shadertoy.com/view/Xl2XWt
// --------------------------------------------------------

const float MAX_TRACE_DISTANCE = 10.;
const float INTERSECTION_PRECISION = .001;
const int NUM_OF_TRACE_STEPS = 150;
const float FUDGE_FACTOR = .5;


vec3 calcNormal(vec3 pos){
    vec3 eps = vec3( 0.0001, 0.0, 0.0 );
    vec3 nor = vec3(
        map(pos+eps.xyy).dist - map(pos-eps.xyy).dist,
        map(pos+eps.yxy).dist - map(pos-eps.yxy).dist,
        map(pos+eps.yyx).dist - map(pos-eps.yyx).dist );
    return normalize(nor);
}

Hit raymarch(vec3 rayOrigin, vec3 rayDirection){

    float currentDist = INTERSECTION_PRECISION * 2.0;
    float rayLength = 0.;
    Model model;

    for(int i = 0; i < NUM_OF_TRACE_STEPS; i++){
        if (currentDist < INTERSECTION_PRECISION || rayLength > MAX_TRACE_DISTANCE) {
            break;
        }
        model = map(rayOrigin + rayDirection * rayLength);
        currentDist = model.dist;
        rayLength += currentDist * (1. - FUDGE_FACTOR);
    }

    bool isBackground = false;
    vec3 pos = vec3(0);
    vec3 normal = vec3(0);

    if (rayLength > MAX_TRACE_DISTANCE) {
        isBackground = true;
    } else {
        pos = rayOrigin + rayDirection * rayLength;
        normal = calcNormal(pos);
    }

    return Hit(model, pos, isBackground, normal, rayOrigin, rayDirection);
}


mat3 calcLookAtMatrix(vec3 ro, vec3 ta, vec3 up) {
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww,up));
    vec3 vv = normalize(cross(uu,ww));
    return mat3(uu, vv, ww);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {

    vec2 p = (-iResolution.xy + 2.0*fragCoord.xy)/iResolution.y;

    // vec3 camPos = vec3(0,0,guiZoom);
    // pR(camPos.xz, iTime);
    // vec3 camTar = vec3(0);
    // vec3 camUp = vec3(0,1,0);
    // mat3 camMat = calcLookAtMatrix(camPos, camTar, camUp);

    camPos = cameraPosition;
    mat4 camMat = cameraMatrix;

    focalLength = pow(guiFocalLength, 3.);
    focalLength = 2.5;
    vec3 rayDirection = normalize(
        (vec4(p, -focalLength, 1) * camMat).xyz
    );

    Hit hit = raymarch(camPos, rayDirection);

    vec3 color = render(hit);
    color = pow(color, vec3(1. / 2.2)); // Gamma
    fragColor = vec4(color,1);
}



