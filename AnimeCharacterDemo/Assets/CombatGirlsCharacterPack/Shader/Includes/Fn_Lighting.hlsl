#ifndef JEFFORD_LIGHTING_INCLUDE
#define JEFFORD_LIGHTING_INCLUDE

#include "ShadingModel.hlsl"
#define UNITY_PI 3.141592653589793

float GetCurvature(float SSSRange, float SSSPower, float3 WorldNormal, float3 WorldPos)
{
    float deltaWorldNormal = length(abs(ddx_fine(WorldNormal)) + abs(ddy_fine(WorldNormal)));
    float deltaWorldPosition = length(abs(ddx_fine(WorldPos)) + abs(ddy_fine(WorldPos))) / 0.001;
    float Curvature = saturate(SSSRange + deltaWorldNormal / deltaWorldPosition * SSSPower);

    return Curvature;
}


inline half3 RotateDirection(half3 R, half degrees = 0)
{
    float3 reflUVW = R;
    half theta = degrees * PI / 180.0f;
    half costha = cos(theta);
    half sintha = sin(theta);
    reflUVW = half3(reflUVW.x * costha - reflUVW.z * sintha, reflUVW.y, reflUVW.x * sintha + reflUVW.z * costha);
    return reflUVW;
}

// Indirect Specular AO
float GetSpecularOcclusion(float NoV, float Roughness, float AO)
{
    float a2 = Roughness * Roughness;
    return saturate(pow(NoV + AO, a2) - 1 + AO);
}

// Indirect Diffuse AO
float3 AOMultiBounce(float3 BaseColor, float AO)
{
    float3 a = 2.0404 * BaseColor - 0.3324;
    float3 b = -4.7951 * BaseColor + 0.6417;
    float3 c = 2.7552 * BaseColor + 0.6903;
    return max(AO, ((AO * a + b) * AO + c) * AO);
}


float3 SpecularGGX_UE4(float Roughness, float3 SpecularColor, float NoH, float NoV, float VoH, float NoL)
{
    float a2 = Pow4(Roughness);

    // Generalized microfacet specular
    float D = D_GGX_UE4(a2, NoH);
    float Vis = Vis_SmithJointApprox_UE4(a2, NoV, NoL);
    float3 F = F_Schlick_UE4(SpecularColor, VoH);
    return (D * Vis) * F;
}

float3 DualSpecularGGX(float Lube0Roughness, float Lube1Roughness, float LubeMix, float3 SpecularColor, float NoH,
                       float NoV, float VoH, float NoL)
{
    float a0 = Pow4(Lube0Roughness);
    float a1 = Pow4(Lube1Roughness);
    float a = Pow4((Lube0Roughness + Lube1Roughness) * 0.5);

    // Generalized microfacet specular
    float D0 = D_GGX_UE4(a0, NoH);
    float D1 = D_GGX_UE4(a1, NoH);
    float D = lerp(D0, D1, 1 - LubeMix);

    float Vis = Vis_SmithJointApprox_UE4(a, NoV, NoL);
    float3 F = F_Schlick_UE4(SpecularColor, VoH);
    return (D * Vis) * F;
}

float3 EnvSpecularDFG(float3 R, float3 SpecularColor, float3 PositionWS,
                      float NoV, half occlusion, float Roughness)
{
    float3 specularLD = GlossyEnvironmentReflection(R, PositionWS, Roughness, occlusion);
    float3 spcularDFG = EnvBRDFApprox(SpecularColor, Roughness, NoV);
    return specularLD * spcularDFG;
}

float3 PBRIndirect(float3 DiffuseColor, float3 SpecularColor, float3 PositionWS, float3 V,
                   float3 N, float3 SH, half occlusion, float Roughness,
                   float EnvRoation)
{
    half3 R = reflect(-V, N);
    R = RotateDirection(R, EnvRoation);
    float NoV = saturate(abs(dot(N, V)) + 0.001);

    float diffuseAO = AOMultiBounce(DiffuseColor, occlusion);
    float specularAO = GetSpecularOcclusion(NoV, Roughness, occlusion);
    specularAO = AOMultiBounce(SpecularColor, specularAO);

    float3 diffuse = DiffuseColor * SH * diffuseAO;
    float3 spcular = EnvSpecularDFG(R, SpecularColor, PositionWS, NoV, occlusion, Roughness) * specularAO;

    float3 c = diffuse + spcular;
    return c;
}


float3 PBRDirect_UE4(float3 DiffuseColor, float3 SpecularColor, float3 V,
                     float3 N, float3 L, float3 lightColor, float atten, float Roughness)
{
    float3 H = normalize(L + V);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float NoV = saturate(abs(dot(N, V)) + 0.001);
    float VoH = saturate(dot(V, H));

    float3 radiance = NoL * lightColor * atten;

    float3 specular = SpecularGGX_UE4(Roughness, SpecularColor, NoH, NoV, VoH, NoL);
    float3 diffuse = Diffuse_Lambert_UE4(DiffuseColor);
    float3 c = specular + diffuse;
    return c * radiance * UNITY_PI;
}


float3 StanderdPBRLighting_float(float3 DiffuseColor, float3 SpecularColor, float3 viewWS, float3 positionWS,
                                 float3 normalWS,
                                 float roughness, float ao, float EnvRotation)
{
    float3 sh = SampleSH(normalWS);
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light light = GetMainLight(shadowCoord, positionWS, 1);
    float atten = light.distanceAttenuation * light.shadowAttenuation;

    float3 directLighting = PBRDirect_UE4(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                          light.color, atten, roughness);

    float3 indirectLighting = PBRIndirect(DiffuseColor, SpecularColor, positionWS,
                                          viewWS, normalWS, sh, ao, roughness,
                                          EnvRotation);

    float3 color = directLighting + indirectLighting;


    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, positionWS);
        {
                atten = light.distanceAttenuation * light.shadowAttenuation;
                color+= PBRDirect_UE4(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                                   light.color, atten, roughness);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
         Light light = GetAdditionalLight(lightIndex, positionWS);
        {
  
                atten = light.distanceAttenuation * light.shadowAttenuation;
               color += PBRDirect_UE4(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                           light.color, atten, roughness);
            

        }
    LIGHT_LOOP_END
    #endif

    return color;
}


#endif
