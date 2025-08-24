#ifndef CLOTH_LIGHTING_INCLUDE
#define CLOTH_LIGHTING_INCLUDE

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#include "ShadingModel.hlsl"
#include "Fn_Lighting.hlsl"
#define UNITY_PI 3.141592653589793

float3 SpecularGGX_Aniso(float3 SpecularColor, float Roughness, float Anisotropy, float NoH, float NoV, float VoH,
                         float NoL, float XoH, float YoH, float XoV, float XoL, float YoV, float YoL)
{
    float Alpha = Roughness * Roughness;
    float a2 = Alpha * Alpha;
    float ax = max(Alpha * (1.0 + Anisotropy), 0.001f);
    float ay = max(Alpha * (1.0 - Anisotropy), 0.001f);

    float D = D_GGXaniso(ax, ay, NoH, XoH, YoH);
    float Vis = Vis_SmithJointAniso(ax, ay, NoV, NoL, XoV, XoL, YoV, YoL);
    float3 F = F_Schlick_UE4(SpecularColor, VoH);
    return (D * Vis) * F;
}

float3 SpecularGGX_Cloth(float Roughness, float NoH, float NoV, float VoH, float NoL)
{
    float D = D_Charlie_Filament(Roughness, NoH);
    float Vis = Vis_Cloth(NoV, NoL);
    float3 F = F_Schlick_UE4(float3(0.04, 0.04, 0.04), VoH);
    return (D * Vis) * F;
}

float3 SpecularGGX_Sheen(float Roughness, float NoH, float NoV, float NoL, float3 SheenColor)
{
    float D = D_Charlie_Filament(Roughness, NoH);
    float Vis = Vis_Cloth(NoV, NoL);
    float3 F = SheenColor;
    return (D * Vis) * F;
}


float3 AnisoIndirectLighting(float3 DiffuseColor, float3 SpecularColor, float3 PositionWS, float3 V,
                             float3 N, float3 TangentWS, float3 BTangentWS, float3 SH, half occlusion, float Roughness,
                             float EnvRoation, float Anisotropy)
{
    float3 anisoDir = Anisotropy >= 0.0 ? BTangentWS : TangentWS;
    float3 aniso_T = cross(anisoDir, V);
    float3 aniso_N = cross(aniso_T, anisoDir);
    N = normalize(lerp(N, aniso_N, abs(Anisotropy)));

    half3 R = reflect(-V, N);
    R = RotateDirection(R, EnvRoation);
    float NoV = saturate(abs(dot(N, V)) + 0.001);

    float diffuseAO = AOMultiBounce(DiffuseColor, occlusion);
    float3 diffuse = DiffuseColor * SH * diffuseAO;

    float specularAO = GetSpecularOcclusion(NoV, Roughness, occlusion);
    specularAO = AOMultiBounce(float3(0.04, 0.04, 0.04), specularAO);

    float3 specularLD = GlossyEnvironmentReflection(R, PositionWS, Roughness, 1.0);
    float3 spcularDFG = EnvSpecularDFG(R, SpecularColor, PositionWS, NoV, occlusion, Roughness);
    float3 spcular = specularLD * spcularDFG * specularAO;

    float3 c = diffuse + spcular;
    return c;
}


float3 AnisoDirectLighting(float3 DiffuseColor, float3 SpecularColor, float3 V, float3 N, float3 L, float3 TangentWS,
                           float3 BTangentWS, float3 lightColor, float atten, float Roughness, float Anisotropy)
{
    float3 H = normalize(L + V);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float NoV = saturate(abs(dot(N, V)) + 0.001);
    float VoH = saturate(dot(V, H));

    float XoH = dot(TangentWS, H);
    float YoH = dot(BTangentWS, H);
    float XoV = dot(TangentWS, V);
    float XoL = dot(TangentWS, L);
    float YoV = dot(BTangentWS, V);
    float YoL = dot(BTangentWS, L);

    float3 radiance = NoL * lightColor * atten;
    float3 specular = SpecularGGX_Aniso(SpecularColor, Roughness, Anisotropy, NoH, NoV, VoH, NoL, XoH,
                                        YoH, XoV, XoL, YoV, YoL) * radiance;
    float3 diffuse = Diffuse_Lambert_UE4(DiffuseColor) * radiance;

    float3 c = specular + diffuse;
    return c * UNITY_PI;
}


float3 AnisoLighting_float(float3 DiffuseColor, float3 SpecularColor, float3 viewWS, float3 positionWS, float3 normalWS,
                           float3 TangentWS, float3 BTangentWS, float roughness, float Anisotropy, float ao,
                           float EnvRotation)
{
    float3 sh = SampleSH(normalWS);
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light light = GetMainLight(shadowCoord, positionWS, 1);
    float atten = light.distanceAttenuation * light.shadowAttenuation;

    float3 directLighting = AnisoDirectLighting(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                                TangentWS, BTangentWS, light.color, atten, roughness, Anisotropy);

    float3 indirectLighting = AnisoIndirectLighting(DiffuseColor, SpecularColor, positionWS, viewWS, normalWS,
                                                    TangentWS, BTangentWS, sh, ao, roughness, EnvRotation, Anisotropy);

    float3 color = directLighting + indirectLighting;
    /**
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
    **/
    return color;
}


float3 FleeceIndirectLighting(float3 DiffuseColor, float3 SheenColor, float3 PositionWS, float3 V,
                              float3 N, float3 SH, half occlusion, float Roughness, float SheenRoughness,
                              float EnvRoation, float ClothDFG, float SheenDFG)
{
    half3 R = reflect(-V, N);
    R = RotateDirection(R, EnvRoation);
    float NoV = saturate(abs(dot(N, V)) + 0.001);

    float energy = 1 - max(max(SheenColor.r, SheenColor.g), SheenColor.b) * SheenDFG;

    float diffuseAO = AOMultiBounce(DiffuseColor, occlusion);
    float3 diffuse = DiffuseColor * SH * diffuseAO;

    float specularAO = GetSpecularOcclusion(NoV, Roughness, occlusion);
    specularAO = AOMultiBounce(float3(0.04, 0.04, 0.04), specularAO);

    float3 specularLD = GlossyEnvironmentReflection(R, PositionWS, Roughness, 1.0);
    float3 spcularDFG = ClothDFG * 0.04;
    float3 spcular = specularLD * spcularDFG * specularAO;

    float specularAO_sheen = GetSpecularOcclusion(NoV, SheenRoughness, occlusion);
    specularAO_sheen = AOMultiBounce(SheenColor, specularAO_sheen);

    float3 specularLD_Sheen = GlossyEnvironmentReflection(R, PositionWS, SheenRoughness, 1.0);
    float3 spcularDFG_Sheen = SheenColor * SheenDFG;
    float3 specular_Sheen = specularLD_Sheen * spcularDFG_Sheen * specularAO_sheen;

    float3 c = diffuse + spcular;
    return c * energy + specular_Sheen;
}


float3 FleeceDirectLighting(float3 DiffuseColor, float3 SheenColor, float3 V,
                            float3 N, float3 L, float3 lightColor, float atten, float Roughness, float SheenRoughness,
                            float sheenDFG)
{
    float3 H = normalize(L + V);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float NoV = saturate(abs(dot(N, V)) + 0.001);
    float VoH = saturate(dot(V, H));

    // 计算能量守恒
    float energy = 1 - max(max(SheenColor.r, SheenColor.g), SheenColor.b) * sheenDFG;
    float3 radiance = NoL * lightColor * atten;

    float3 specular = SpecularGGX_Cloth(Roughness, NoH, NoV, VoH, NoL) * radiance;
    float3 sheenSpc = SpecularGGX_Sheen(SheenRoughness, NoH, NoV, NoL, SheenColor) * radiance;

    float3 diffuse = Diffuse_Lambert_UE4(DiffuseColor) * radiance;

    float3 c = specular + diffuse;
    return c * UNITY_PI * energy + sheenSpc;
}


float3 FleeceLighting_float(float3 DiffuseColor, float3 SheenColor, float3 viewWS, float3 positionWS, float3 normalWS,
                            float roughness, float SheenRoughness, float ao, float EnvRotation, float sheenDFG,
                            float ClothDFG)
{
    float3 sh = SampleSH(normalWS);
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light light = GetMainLight(shadowCoord, positionWS, 1);
    float atten = light.distanceAttenuation * light.shadowAttenuation;

    float3 directLighting = FleeceDirectLighting(DiffuseColor, SheenColor, viewWS, normalWS, light.direction,
                                                 light.color, atten, roughness, SheenRoughness, sheenDFG);

    float3 indirectLighting = FleeceIndirectLighting(DiffuseColor, SheenColor, positionWS,
                                                     viewWS, normalWS, sh, ao, roughness, SheenRoughness,
                                                     EnvRotation, ClothDFG, sheenDFG);

    float3 color = directLighting + indirectLighting;
    /**
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
    **/
    return color;
}


#endif
