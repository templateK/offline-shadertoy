precision highp float;

uniform vec2 iResolution;

#define MIRROR

vec2 texSubdivisions = vec2(22,4);
// voxel resolution is
// vec3(
//     iResolution / texSubdivisions,
//     texSubdivisions.x * texSubdivisions.y * 4.
// );
//

// #define SCALE (vec3(4.1,1.73,1.75) * 1.1)
// #define OFFSET vec3(.95, .094, -.088)

#define SCALE (vec3(4.1,1.73,1.75)/1.2)
#define OFFSET vec3(.95, .094, -.088)


// #define SCALE vec3(1)
// #define OFFSET vec3(0)


// Divide texture into 3d space coordinates
// uv = 2d texture coordinates 0:1
// c = channel 0:3

// xy is split for each z

// Returns matrix representing four positions in space
// vec3 p0 = mat4[0].xyz;
// vec3 p1 = mat4[1].xyz;
// vec3 p2 = mat4[2].xyz;
// vec3 p3 = mat4[4].xyz;
float round(float t) { return floor(t + 0.5); }
vec2 round(vec2 t) { return floor(t + 0.5); }

// current theory its rounding errors when texture doesn't divide

vec3 texToSpace(vec2 coord, int c, vec2 size) {
    vec2 sub = texSubdivisions;
    vec2 subSize = floor(size / sub);
    vec2 subCoord = floor(coord / subSize);
    float z = subCoord.x + subCoord.y * sub.x + float(c) * sub.x * sub.y;
    float zRange = sub.x * sub.y * 4. - 1.;
    z /= zRange;
    vec2 subUv = mod(coord / subSize, 1.);
    vec3 p = vec3(subUv, z);
    p = p * 2. - 1.; // range -1:1
    return p;
}

mat4 texToSpace(vec2 coord, vec2 size) {
    return mat4(
        vec4(texToSpace(coord, 0, size), 0),
        vec4(texToSpace(coord, 1, size), 0),
        vec4(texToSpace(coord, 2, size), 0),
        vec4(texToSpace(coord, 3, size), 0)
    );
}


// Transform xyz coordinate in range -1,-1,-1 to 1,1,1
// to texture uv and channel
vec3 spaceToTex(vec3 p, vec2 size) {
    p = clamp(p, -1., 1.);
    p = p * .5 + .5; // range 0:1

    vec2 sub = texSubdivisions;
    vec2 subSize = floor(size / sub);

    // uv = clamp(uv, 0., 1.);

    // Work out the z index
    float zRange = sub.x * sub.y * 4. - 1.;
    float i = round(p.z * zRange);

    // return vec3(i/zRange);

    // return vec3(mod(i, sub.x)/sub.x);
    // translate uv into the micro offset in the z block
    vec2 coord = p.xy * subSize;

    // Work out the macro offset for the xy block from the z block
    coord += vec2(
        mod(i, sub.x),
        mod(floor(i / sub.x), sub.y)
    ) * subSize;

    float c = floor(i / (sub.x * sub.y));

    return vec3(coord / size, c);
}

float range(float vmin, float vmax, float value) {
  return clamp((value - vmin) / (vmax - vmin), 0., 1.);
}

float pickIndex(vec4 v, int i) {
    if (i == 0) return v.r;
    if (i == 1) return v.g;
    if (i == 2) return v.b;
    if (i == 3) return v.a;
}

float mapTex(sampler2D tex, vec3 p, vec2 size) {
    // stop x bleeding into the next cell as it's the mirror cut
    #ifdef MIRROR
        p.x = clamp(p.x, -.95, .95);
    #endif
    vec2 sub = texSubdivisions;
    float zRange = sub.x * sub.y * 4. - 1.;
    float z = p.z * .5 + .5; // range 0:1
    float zFloor = (floor(z * zRange) / zRange) * 2. - 1.;
    float zCeil = (ceil(z * zRange) / zRange) * 2. - 1.;
    vec3 uvcA = spaceToTex(vec3(p.xy, zFloor), size);
    vec3 uvcB = spaceToTex(vec3(p.xy, zCeil), size);
    float a = pickIndex(texture2D(tex, uvcA.xy), int(uvcA.z));
    float b = pickIndex(texture2D(tex, uvcB.xy), int(uvcB.z));
    return mix(a, b, range(zFloor, zCeil, p.z));
}

void mainImage(out vec4 a, in vec2 b);

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}

