#ifndef EYE_LIGHTING_INCLUDE
#define EYE_LIGHTING_INCLUDE

#include "ShadingModel.hlsl"
 #include "Fn_Lighting.hlsl"

#define UNITY_PI 3.141592653589793

struct EyeData
{
    float3 DiffuseColor;
    float3 SpecularColor;
    float Roughness;
    half3 WorldPos;
    half3 WorldNormal;
    half3 ViewDir;
    half Occlusion;
    half EnvRotation;
    float IrisMask;
    float3 IrisNormal;
    float3 CausticNormal;
    Texture2D SSSLUT;
    SamplerState sampler_SSSLUT;
};


void EyeRefraction_float(float2 UV, float3 NormalDir, float3 ViewDir, half IOR,
                         float IrisUVRadius, float IrisDepth, float3 EyeDirection, float3 WorldTangent,
                         out float2 IrisUV, out float IrisConcavity)
{
    IrisUV = float2(0.5, 0.5);
    IrisConcavity = 1.0;

    float3 RefractedViewDir = RefractDirection(IOR, NormalDir, ViewDir);
    float cosAlpha = dot(ViewDir, EyeDirection);
    cosAlpha = lerp(0.325, 1, cosAlpha * cosAlpha);
    RefractedViewDir = RefractedViewDir * (IrisDepth / cosAlpha);


    float3 TangentDerive = normalize(WorldTangent - dot(WorldTangent, EyeDirection) * EyeDirection);
    float3 BiTangentDerive = normalize(cross(EyeDirection, TangentDerive));
    float RefractUVOffsetX = dot(RefractedViewDir, TangentDerive);
    float RefractUVOffsetY = dot(RefractedViewDir, BiTangentDerive);
    float2 RefractUVOffset = float2(-RefractUVOffsetX, RefractUVOffsetY);
    float2 UVRefract = UV + IrisUVRadius * RefractUVOffset;

    IrisUV = (UVRefract - float2(0.5, 0.5)) / IrisUVRadius * 0.5 + float2(0.5, 0.5);
    IrisConcavity = length(UVRefract - float2(0.5, 0.5)) * IrisUVRadius;
}

half3 EyeRefraction(float2 UV, float3 NormalDir, float3 ViewDir, half IOR,
                    float IrisUVRadius, float IrisDepth, float3 EyeDirection, float3 WorldTangent)
{
    float2 IrisUV = float2(0.5, 0.5);
    float IrisConcavity = 1.0;


    float3 RefractedViewDir = RefractDirection(IOR, NormalDir, ViewDir);
    float cosAlpha = dot(ViewDir, EyeDirection);
    cosAlpha = lerp(0.325, 1, cosAlpha * cosAlpha);
    RefractedViewDir = RefractedViewDir * (IrisDepth / cosAlpha);


    float3 TangentDerive = normalize(WorldTangent - dot(WorldTangent, EyeDirection) * EyeDirection);
    float3 BiTangentDerive = normalize(cross(EyeDirection, TangentDerive));
    float RefractUVOffsetX = dot(RefractedViewDir, TangentDerive);
    float RefractUVOffsetY = dot(RefractedViewDir, BiTangentDerive);
    float2 RefractUVOffset = float2(-RefractUVOffsetX, RefractUVOffsetY);
    float2 UVRefract = UV + IrisUVRadius * RefractUVOffset;

    IrisUV = (UVRefract - float2(0.5, 0.5)) / IrisUVRadius * 0.5 + float2(0.5, 0.5);
    IrisConcavity = length(UVRefract - float2(0.5, 0.5)) * IrisUVRadius;
    return half3(IrisUV, IrisConcavity);
}


half3 EyeBxDF(half3 DiffuseColor, half3 SpecularColor, float Roughness, half3 N, half3 V, half3 L,
              half IrisMask, half3 IrisNormal, half3 CausticNormal,
              half3 LightColor, float Shadow, float3 DiffuseShadow, Texture2D SSSLUT, SamplerState sampler_SSSLUT)
{
    float3 H = normalize(V + L);
    float NoH = saturate(dot(N, H));
    float NoV = saturate(abs(saturate(dot(N, V))) + 1e-5);
    float NoL = saturate(dot(N, L));
    float VoH = saturate(dot(V, H));

    float IrisNoL = saturate(dot(IrisNormal, L));
    float Power = lerp(12, 1, IrisNoL);
    float Caustic = 0.3 + (0.8 + 0.2 * (Power + 1)) * pow(saturate(dot(CausticNormal, L)), Power); //��ɢ
    IrisNoL = IrisNoL * Caustic;

    float3 ScleraNoL = SAMPLE_TEXTURE2D(SSSLUT, sampler_SSSLUT, half2(dot(N, L) * 0.5 + 0.5,0.9)).rgb;
    float3 NoL_Diff = lerp(ScleraNoL, IrisNoL, IrisMask);
    float3 DiffIrradiance = LightColor * PI * DiffuseShadow * NoL_Diff;
    half3 DiffuseLighting = Diffuse_Lambert_UE4(DiffuseColor) * DiffIrradiance;
    #if defined(_DIFFUSE_OFF)
    DiffuseLighting = float3(0,0,0);
    #endif

    float3 SpecIrradiance = LightColor * PI * Shadow * NoL;
    half3 SpecularLighting = SpecularGGX_UE4(Roughness, SpecularColor, NoH, NoV, NoL, VoH) * SpecIrradiance;
    float F = F_Schlick_UE4(0.04, VoH) * IrisMask;
    float Fcc = 1.0 - F;
    DiffuseLighting *= Fcc;
    return DiffuseLighting + SpecularLighting;
}

void EyeDirectLighting_float(float3 DiffuseColor, float3 SpecularColor, float Roughness, float3 WorldPos,
                             half3 WorldNormal, half3 ViewDir, half IrisMask, half3 IrisNormal, half3 CausticNormal,
                             Texture2D SSSLUT, SamplerState sampler_SSSLUT, out float3 DirectLighting)
{
    DirectLighting = float3(0.5, 0.5, 0);
    #ifndef SHADERGRAPH_PREVIEW
    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
        float4 clipPos = TransformWorldToHClip(WorldPos);
        float4 ShadowCoord = ComputeScreenPos(clipPos);
    #else
    float4 ShadowCoord = TransformWorldToShadowCoord(WorldPos);
    #endif
    float ShadowMask = float4(1.0, 1.0, 1.0, 1.0);

    half3 N = WorldNormal;
    half3 V = ViewDir;

    half3 DirectLighting_MainLight = half3(0, 0, 0);
    {
        Light light = GetMainLight(ShadowCoord, WorldPos, ShadowMask);
        half3 L = light.direction;
        half3 LightColor = light.color;
        float Shadow = saturate(light.shadowAttenuation + 0.2);
        half3 DiffuseShadow = lerp(half3(0.11, 0.025, 0.012), half3(1, 1, 1), Shadow); //hard code;
        DirectLighting_MainLight = EyeBxDF(DiffuseColor, SpecularColor, Roughness, N, V, L,
                                           IrisMask, IrisNormal, CausticNormal, LightColor, Shadow, DiffuseShadow,
                                           SSSLUT, sampler_SSSLUT);
    }

    half3 DirectLighting_AddLight = half3(0, 0, 0);
    #if defined(_ADDITIONAL_LIGHTS)
        int pixelLightCount = GetAdditionalLightsCount();
        for (int lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
        {
            Light light = GetAdditionalLight(lightIndex, WorldPos,ShadowMask);
            half3 L = light.direction;
            half3 LightColor = light.color;
            float Shadow = saturate(light.shadowAttenuation + 0.2) * light.distanceAttenuation;
            half3 DiffuseShadow = lerp(half3(0.11,0.025,0.012),half3(1,1,1),Shadow);//hard code;
            DirectLighting_AddLight += EyeBxDF(DiffuseColor,SpecularColor,Roughness,N,V,L,
                                        IrisMask,IrisNormal,CausticNormal,LightColor,Shadow,DiffuseShadow,SSSLUT,sampler_SSSLUT);
        }
    #endif
    DirectLighting = DirectLighting_MainLight + DirectLighting_AddLight;
    #endif
}


void EyeIndirectLighting_float(float3 DiffuseColor, float3 SpecularColor, float Roughness, half3 WorldPos,
                               half3 WorldNormal, half3 ViewDir,
                               half Occlusion, half EnvRotation, out float3 IndirectLighting)
{
    IndirectLighting = float3(0, 0, 0);
    #ifndef SHADERGRAPH_PREVIEW
    float3 N = WorldNormal;
    float3 V = ViewDir;
    float NoV = saturate(abs(dot(N, V)) + 1e-5);
    half DiffuseAO = Occlusion;
    half SpecualrAO = GetSpecularOcclusion(NoV, Pow2(Roughness), Occlusion);
    half3 DiffOcclusion = AOMultiBounce(DiffuseColor, DiffuseAO);
    half MainLightShadow = clamp(GetMainLightShadow(WorldPos), 0.3, 1.0);
    half3 SpecOcclusion = AOMultiBounce(SpecularColor, SpecualrAO * MainLightShadow);

    half3 IrradianceSH = SampleSH(N);
    half3 IndirectDiffuse = DiffuseColor * IrradianceSH * DiffOcclusion;
    #if defined(_SH_OFF)
    IndirectDiffuse = float3(0,0,0);
    #endif

    half3 R = reflect(-V, N);
    R = RotateDirection(R, EnvRotation);
    half3 EnvSpecularLobe = EnvSpecularDFG(R, SpecularColor, WorldPos, NoV, 1, Roughness);

    half3 IndirectSpecular = EnvSpecularLobe * SpecOcclusion;

    IndirectLighting = IndirectDiffuse + IndirectSpecular;

    #endif
}

half3 EyePhysicallyBasedLighting(EyeData eyeData)
{
    float3 DiffuseColor = eyeData.DiffuseColor;
    float3 SpecularColor = eyeData.SpecularColor * 0.08;
    float Roughness = max(0.001, eyeData.Roughness);
    half3 WorldPos = eyeData.WorldPos;
    half3 WorldNormal = eyeData.WorldNormal;
    half3 ViewDir = eyeData.ViewDir;
    half Occlusion = eyeData.Occlusion;
    half EnvRotation = eyeData.EnvRotation;
    float IrisMask = eyeData.IrisMask;
    float3 IrisNormal = eyeData.IrisNormal;
    float3 CausticNormal = eyeData.CausticNormal;
    Texture2D SSSLUT = eyeData.SSSLUT;
    SamplerState sampler_SSSLUT = eyeData.sampler_SSSLUT;

    half3 directLighting = 0;
    EyeDirectLighting_float(DiffuseColor, SpecularColor, Roughness, WorldPos,
                            WorldNormal, ViewDir, IrisMask, IrisNormal, CausticNormal,
                            SSSLUT, sampler_SSSLUT, directLighting);

    half3 indirectLighting = 0;
    EyeIndirectLighting_float(DiffuseColor, SpecularColor, Roughness, WorldPos, WorldNormal, ViewDir,
                              Occlusion, EnvRotation, indirectLighting);
    half3 color = directLighting + indirectLighting;
    return color;
}

half3 EyePhysicallyBasedLighting(float3 DiffuseColor, float3 SpecularColor, half3 WorldPos,
                                 half3 SurfaceNormal, half3 ViewDir, float3 IrisNormal, float3 CausticNormal,
                                 half Occlusion, float Roughness, half EnvRotation, float IrisMask, Texture2D SSSLUT,
                                 SamplerState sampler_SSSLUT)
{
    SpecularColor = SpecularColor * 0.08;
    Roughness = max(0.001, Roughness);

    half3 directLighting = 0;
    EyeDirectLighting_float(DiffuseColor, SpecularColor, Roughness, WorldPos,
                            SurfaceNormal, ViewDir, IrisMask, IrisNormal, CausticNormal,
                            SSSLUT, sampler_SSSLUT, directLighting);

    half3 indirectLighting = 0;
    EyeIndirectLighting_float(DiffuseColor, SpecularColor, Roughness, WorldPos, SurfaceNormal, ViewDir,
                              Occlusion, EnvRotation, indirectLighting);
    half3 color = directLighting + indirectLighting;
    return color;
}


#endif
