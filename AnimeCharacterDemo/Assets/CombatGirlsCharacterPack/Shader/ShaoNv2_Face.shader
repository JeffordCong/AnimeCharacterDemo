Shader "Demo/ShaoNv2/Face"
{
    Properties
    {
        _ForwardDir("Forward Dir",Vector) = (0,0,1,0)
        _RightDir("Right Dir",Vector) = (1,0,0,0)

        _BaseColor("Base Color",color) = (1,1,1,1)
        _BaseMap("BaseMap", 2D) = "white" {}
        _DarkColor("Dark Color",color) = (1,1,1,1)
        _SpecColor("Spec Color",color) = (1,1,1,1)
        _SDFMap("SDF Map", 2D) = "white" {}
        _LightOffset("Light Offset",Range(0,1)) = 0
        _ShadowStrenth("Shadow Strenth",Range(0,1)) = 0


        [Header(Stencil)]
        _StencilRef ("_StencilRef", Range(0, 255)) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)]_StencilComp ("_StencilComp", Float) = 0

        _OutLineColor("OutLine Color",color) = (1,1,1,1)
        _OutLine("OutLine",Float) = 0.5
    }

    SubShader
    {

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Stencil
            {
                Ref [_StencilRef]
                Comp [_StencilComp]
                Pass replace
            }

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Includes/Fn_Lighting.hlsl"
            #define _NORMALMAP

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _SpecColor;
                float4 _DarkColor;
                float4 _BaseMap_ST;
                float _LightOffset;
                float _ShadowStrenth;

                float3 _ForwardDir;
                float3 _RightDir;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_SDFMap);
            SAMPLER(sampler_SDFMap);


            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
                float2 texcoord1 : TEXCOORD1;
            };

            struct Varyings
            {
                float4 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;
                float3 viewDirWS : TEXCOORD5;
                float4 shadowCoord : TEXCOORD7;
                float4 positionCS : SV_POSITION;
            };


            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                real sign = input.tangentOS.w * GetOddNegativeScale();
                half4 tangentWS = half4(normalInput.tangentWS.xyz, sign);

                o.uv.xy = input.texcoord;
                o.uv.zw = input.texcoord1;
                o.shadowCoord = GetShadowCoord(vertexInput);
                o.positionWS = vertexInput.positionWS;
                o.normalWS = normalInput.normalWS;
                o.tangentWS = tangentWS;
                o.positionCS = vertexInput.positionCS;

                return o;
            }


            half4 frag(Varyings i) : SV_Target
            {
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                baseColor = baseColor * _BaseColor;

                float3 forwardWS = TransformObjectToWorldDir(_ForwardDir, true);
                float3 rightWS = TransformObjectToWorldDir(_RightDir, true);
                forwardWS = float3(forwardWS.x, 0, forwardWS.z);
                rightWS = float3(rightWS.x, 0, rightWS.z);

                forwardWS = normalize(float3(_ForwardDir.x, 0, _ForwardDir.z));
                rightWS = normalize(float3(_RightDir.x, 0,_RightDir.z));

                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light light = GetMainLight(shadowCoord, i.positionWS, half4(1, 1, 1, 1));

                float3 L_sdf = float3(light.direction.x, 0, light.direction.z);
                float3 N = i.normalWS;
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float FoL = saturate(dot(-forwardWS, L_sdf) * 0.5 + _LightOffset);

                float RoL = dot(rightWS, L_sdf);
                float2 sdfUV = i.uv.zw;
                sdfUV.x = lerp(i.uv.z, -i.uv.z, step(0, RoL));
                half sdf_diff = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, sdfUV);
                float step_diff = step(1 - sdf_diff, FoL);

                float2 sdfUV_spec = float2(1 - sdfUV.x, sdfUV.y);
                half3 sdf_spc = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, sdfUV_spec).rgb;
                float FoL_spec = clamp(FoL, 0.001, 0.999);
                float step_spc1 = step(1 - FoL_spec, sdf_spc.g);
                float step_spc2 = step(FoL_spec, sdf_spc.b);
                float step_spc = step_spc1 * step_spc2 * (FoL_spec);

                float4 diffColor = lerp(baseColor, _DarkColor * baseColor, _DarkColor.a * (1 - step_diff));
                float4 specColor = step_spc * _SpecColor * baseColor;
                float3 mainLightColor = diffColor + specColor;
                float3 c = mainLightColor * light.color;

                #if defined(_ADDITIONAL_LIGHTS)
                        uint pixelLightCount = GetAdditionalLightsCount();
                                    
                        LIGHT_LOOP_BEGIN(pixelLightCount)
                            Light light = GetAdditionalLight(lightIndex, i.positionWS, float4(1,1,1,1));
                   
                                c = c * light.color * light.distanceAttenuation;
                
                        LIGHT_LOOP_END
                #endif

                return float4(c, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "OutLine"
            }

            Cull Front

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS :NORMAL;
                float4 tangentOS :TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _OutLineColor;
                half _OutLine;
            CBUFFER_END


            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                float3 normalVS = normalize(mul(UNITY_MATRIX_MV, v.normalOS));
                float3 positionVS = vertexInput.positionVS;
                positionVS = positionVS + normalVS * _OutLine * 0.01 * _OutLineColor.a;

                o.positionCS = mul(UNITY_MATRIX_P, float4(positionVS, 1.0));
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return _OutLineColor;
            }
            ENDHLSL
        }


        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            //  #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Universal Pipeline keywords

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            ColorMask R
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            //     #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags
            {
                "LightMode" = "DepthNormals"
            }

            // -------------------------------------
            // Render State Commands
            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _ _DETAIL_MULX2 _DETAIL_SCALED
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // -------------------------------------
            // Universal Pipeline keywords
            //   #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            //    #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}