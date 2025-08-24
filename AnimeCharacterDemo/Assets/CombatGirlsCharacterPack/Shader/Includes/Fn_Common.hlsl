#ifndef JEFFORD_COMMON_INCLUDE
#define JEFFORD_COMMON_INCLUDE

float Pow5(float x)
{
    return x * x * x * x * x;
}

float Pow2(float x)
{
    return x * x;
}

void GetSSAO_float(float2 ScreenUV,out float SSAO)
{
    SSAO = 1.0f;
    #ifndef SHADERGRAPH_PREVIEW
    #if defined(_SCREEN_SPACE_OCCLUSION)
    AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(ScreenUV);
    SSAO = aoFactor.indirectAmbientOcclusion;
    #endif
    #endif
}

half2 ScaleUVsByCenter_float(half2 UVs, float Scale)
{
    Scale = max(0.0001, Scale);
    return (UVs / Scale + (0.5).xx) - (0.5 / Scale).xx;
}

half2 ScaleUVsByCenter(half2 UVs, float Scale)
{
    Scale = max(0.0001, Scale);
    return (UVs / Scale + (0.5).xx) - (0.5 / Scale).xx;
}

half2 ScaleUVFromCircle_float(half2 UV, float Scale)
{
    float2 UVcentered = UV - float2(0.5f, 0.5f);
    float UVlength = length(UVcentered);
    // UV on circle at distance 0.5 from the center, in direction of original UV
    float2 UVmax = normalize(UVcentered) * 0.5f;

    float2 UVscaled = lerp(UVmax, float2(0.f, 0.f), saturate((1.f - UVlength * 2.f) * Scale));
    return UVscaled + float2(0.5f, 0.5f);
}

half2 ScaleUVFromCircle(half2 UV, float Scale)
{
    float2 UVcentered = UV - float2(0.5f, 0.5f);
    float UVlength = length(UVcentered);
    // UV on circle at distance 0.5 from the center, in direction of original UV
    float2 UVmax = normalize(UVcentered) * 0.5f;

    float2 UVscaled = lerp(UVmax, float2(0.f, 0.f), saturate((1.f - UVlength * 2.f) * Scale));
    return UVscaled + float2(0.5f, 0.5f);
}

float3 RefractDirection(float internalIoR, float3 WorldNormal, float3 incidentVector)
{
    float airIoR = 1.00029;
    float n = airIoR / internalIoR;
    float facing = dot(WorldNormal, incidentVector);
    float w = n * facing;
    float k = sqrt(1 + (w - n) * (w + n));
    float3 t = -normalize((w - k) * WorldNormal - n * incidentVector);
    return t;
}

float GetMainLightShadow(float3 WorldPos)
{
    #ifndef SHADERGRAPH_PREVIEW
    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
    float4 clipPos = TransformWorldToHClip(WorldPos);
    float4 ShadowCoord = ComputeScreenPos(clipPos);
    #else
    float4 ShadowCoord = TransformWorldToShadowCoord(WorldPos);
    #endif
    float ShadowMask = float4(1.0, 1.0, 1.0, 1.0);
    Light MainLight = GetMainLight(ShadowCoord, WorldPos, ShadowMask);
    half Shadow = MainLight.shadowAttenuation;
    return Shadow;
    #endif
    return 1.0;
}

#endif
