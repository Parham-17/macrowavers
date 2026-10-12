#include <metal_stdlib>
using namespace metal;

// Parâmetros fixos de cada vértice (gerados uma vez na CPU).
// kind: 0 = face de cima da fatia (polpa)
//       1 = face de baixo da fatia (polpa)
//       2 = casca (parede externa)
struct VertexParams {
    float theta;   // ângulo ao longo da espiral
    float s;       // 0 = centro, 1 = borda (faces de polpa)
    float v;       // 0 = base, 1 = topo da fatia (casca)
    uint  kind;
};

// Precisa bater com AppleVertex em Swift (float3 = 16 bytes).
struct OutVertex {
    float3 position;
    float3 normal;
};

struct Uniforms {
    float opening;     // 0 = fechada, 1 = totalmente aberta
    float height;
    float maxRadius;
    float turns;
    float gapPerTurn;
    uint  vertexCount;
};

// Perfil da maçã: raio em função da altura.
static float appleRadius(float h, constant Uniforms& u) {
    float t = clamp(h / u.height, 0.0, 1.0);
    return u.maxRadius * (0.12 + 0.88 * sqrt(max(sin(M_PI_F * t), 0.0)));
}

// Posição de um ponto da superfície para uma dada abertura.
static float3 applePoint(float theta, float s, float v, uint kind, constant Uniforms& u) {
    float pitch = u.height / (u.turns + 1.0);
    float turn  = theta / (2.0 * M_PI_F);

    // Altura original (maçã fechada) da base e do topo da fatia neste ângulo.
    float yb = clamp(turn * pitch, 0.0, u.height);
    float yt = clamp((turn + 1.0) * pitch, 0.0, u.height);

    // Quanto a fatia sobe quando a maçã abre: cresce a cada volta.
    float lift = u.opening * u.gapPerTurn * clamp(turn, 0.0, u.turns);

    float h, r;
    if (kind == 0)      { h = yt;              r = appleRadius(h, u) * s; }
    else if (kind == 1) { h = yb;              r = appleRadius(h, u) * s; }
    else                { h = mix(yb, yt, v);  r = appleRadius(h, u); }

    return float3(r * cos(theta), h + lift, r * sin(theta));
}

kernel void deformApple(device const VertexParams* params [[buffer(0)]],
                        device OutVertex*          out    [[buffer(1)]],
                        constant Uniforms&         u      [[buffer(2)]],
                        uint id [[thread_position_in_grid]])
{
    if (id >= u.vertexCount) return;
    VertexParams p = params[id];

    float3 pos = applePoint(p.theta, p.s, p.v, p.kind, u);

    // Normal por diferenças finitas, avaliando a mesma função ao redor do ponto.
    // No eixo central (s = 0) a derivada degenera, então avaliamos um pouco fora.
    const float e = 0.002;
    float sEval = (p.kind == 2) ? p.s : max(p.s, 0.05);

    float3 dTheta = applePoint(p.theta + e, sEval, p.v, p.kind, u)
                  - applePoint(p.theta - e, sEval, p.v, p.kind, u);
    float3 dOther = (p.kind == 2)
        ? applePoint(p.theta, sEval, p.v + e, p.kind, u) - applePoint(p.theta, sEval, p.v - e, p.kind, u)
        : applePoint(p.theta, sEval + e, p.v, p.kind, u) - applePoint(p.theta, sEval - e, p.v, p.kind, u);

    float3 n = cross(dTheta, dOther);
    float3 radial = float3(pos.x, 0.0, pos.z);

    if (length(n) < 1e-8) {
        // Fallback onde a fatia tem espessura zero (pontas da espiral).
        n = (p.kind == 0) ? float3(0, 1, 0)
          : (p.kind == 1) ? float3(0, -1, 0)
          : radial;
    }
    n = normalize(n);

    // Garante que a normal aponte para fora.
    if (p.kind == 0 && n.y < 0) n = -n;
    if (p.kind == 1 && n.y > 0) n = -n;
    if (p.kind == 2 && dot(n, radial) < 0) n = -n;

    out[id].position = pos;
    out[id].normal   = n;
}
