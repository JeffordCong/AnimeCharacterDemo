using UnityEngine;
using UnityEditor;
using System.Collections.Generic;
using MagicaCloth;
public class UpdateSkinnedMeshWindow : EditorWindow
{
    [MenuItem("美术/Skinned Mesh Tools", false, 7001)]
    public static void OpenWindow()
    {
        var window = GetWindow<UpdateSkinnedMeshWindow>();
        window.titleContent = new GUIContent("Skin Updater");
    }
    public Transform m_TargetRig;
    public List<Transform> m_DonorRigs = new List<Transform>();
    public Transform[] m_DonorRigsArray;
    private SkinnedMeshRenderer[] m_DonorSkinnedMeshRenders;
    private Transform[] m_DonorBones;
    private SkinnedMeshRenderer m_TargetSkinnedMeshRenderer;
    private Transform[] m_TargetBones;

    private List<string> addedBones = new List<string>();
    private string addedBoneslabel;

    public Transform m_BaseRig;
    public Transform m_TargetCollider;
    public bool m_IsMagicaCloth = true;

    public Transform m_OriginColliderRoot;
    public Transform m_DestColliderRoot;
    private void OnGUI()
    {
        m_TargetRig = EditorGUILayout.ObjectField("Base Skin", m_TargetRig, typeof(Transform), true) as Transform;
        ScriptableObject target = this;
        SerializedObject so = new SerializedObject(target);
        SerializedProperty stringsProperty = so.FindProperty("m_DonorRigsArray");
        EditorGUILayout.PropertyField(stringsProperty,new GUIContent("Merged Skin"), true); // True means show children
        so.ApplyModifiedProperties(); // Remember to apply modified properties
        if(m_DonorRigsArray != null)
            m_DonorRigs = new List<Transform>(m_DonorRigsArray);
        //includeInactive = EditorGUILayout.Toggle("Include Inactive", includeInactive);
        bool enabled = (m_TargetRig != null && m_DonorRigs != null);
        bool isPrefab = false;
        if (m_TargetRig != null)
        {
            var prefabtype = PrefabUtility.GetPrefabAssetType(m_TargetRig);
            isPrefab = prefabtype == PrefabAssetType.NotAPrefab ? false : true;
        }
        if (m_DonorRigs != null)
        {
            foreach (var donorRig in m_DonorRigs)
            {
                var prefabtype = PrefabUtility.GetPrefabAssetType(donorRig);
                isPrefab |= prefabtype == PrefabAssetType.NotAPrefab ? false : true;
            }
        }
        if (isPrefab)
        {
            GUILayout.Label("��⿪Ԥ������");
        }
        //GUI.enabled = enabled;
        if (enabled && !isPrefab)
        {
            if (GUILayout.Button("Update Skinned Mesh Renderer"))
            {
                TransferSMRList();
            }
            EditorGUILayout.SelectableLabel(addedBoneslabel,GUILayout.Height(500));
        }
        GUILayout.Space(50);
        m_BaseRig = EditorGUILayout.ObjectField("Base Rig Hip", m_BaseRig, typeof(Transform), true) as Transform;
        m_TargetCollider = EditorGUILayout.ObjectField("Target Rig Hip", m_TargetCollider, typeof(Transform), true) as Transform;
        if (m_BaseRig != null && m_TargetCollider != null)
        {
            m_IsMagicaCloth = EditorGUILayout.Toggle(m_IsMagicaCloth, "Is Magica Cloth");
            if (GUILayout.Button("Transfer Collider"))
            {
                TransferCollierList(m_IsMagicaCloth);
            }
        }
        GUILayout.Space(50);
        m_OriginColliderRoot = EditorGUILayout.ObjectField("Origin", m_OriginColliderRoot, typeof(Transform), true) as Transform;
        m_DestColliderRoot = EditorGUILayout.ObjectField("Target", m_DestColliderRoot, typeof(Transform), true) as Transform;
        if (m_OriginColliderRoot != null && m_DestColliderRoot != null)
        {
            if (GUILayout.Button("Copy Magica Collider"))
            {
                CopyMagicaColliders();
            }
        }
    }

    private void TransferSMRList()
    {

        for (int r = 0; r < m_DonorRigs.Count; r++)
        {
            m_DonorRigs[r].position = m_TargetRig.position;
            m_DonorRigs[r].rotation = m_TargetRig.rotation;
            m_DonorSkinnedMeshRenders = m_DonorRigs[r].GetComponentsInChildren<SkinnedMeshRenderer>();
            foreach (var m_DonorSkinnedMeshRender in m_DonorSkinnedMeshRenders)
            {
                m_DonorBones = m_DonorSkinnedMeshRender.bones;
                m_TargetSkinnedMeshRenderer = m_TargetRig.GetComponentInChildren<SkinnedMeshRenderer>();
                m_TargetBones = m_TargetSkinnedMeshRenderer.bones;
                for (int i = 0; i < m_DonorBones.Length; i++)
                {
                    if (m_DonorBones[i] == null)
                        continue;
                    string boneName = m_DonorBones[i].name;
                    bool found = false;
                    for (int j = 0; j < m_TargetBones.Length; j++)
                    {
                        if (m_TargetBones[j] != null)
                        {
                            if (m_TargetBones[j].name == boneName)
                            {
                                m_DonorBones[i] = m_TargetBones[j];
                                found = true;
                            }
                        }
                    }
                    if (!found)
                    {
                        string boneParent = m_DonorBones[i].transform.parent.name;
                        for (int j = 0; j < m_TargetBones.Length; j++)
                        {
                            if (m_TargetBones[j] != null)
                            {
                                if (m_TargetBones[j].name == boneParent)
                                {
                                    bool alreadyadd = false;
                                    foreach (var addedBone in addedBones)
                                    {
                                        if (addedBone.ToString() == m_DonorBones[i].name)
                                        {
                                            alreadyadd = true;
                                        }
                                    }
                                    if (!alreadyadd)
                                    {
                                        m_DonorBones[i].transform.parent = m_TargetBones[j];
                                        addedBones.Add(m_DonorBones[i].name);
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
                m_DonorSkinnedMeshRender.bones = m_DonorBones;
                m_DonorSkinnedMeshRender.rootBone = m_TargetSkinnedMeshRenderer.rootBone;
                m_DonorSkinnedMeshRender.transform.parent = m_TargetSkinnedMeshRenderer.transform.parent;
            }
        }
        foreach (var addedBone in addedBones)
        {
            addedBoneslabel += System.Environment.NewLine + "����bone:" + addedBone;
        }
    }

    private void TransferCollierList(bool isMagicaCloth = true)
    {
        var target_Colliders = m_TargetCollider.GetComponentsInChildren<SphereCollider>();
        var m_base_rigbones = m_BaseRig.GetComponentsInChildren<Transform>();
        foreach (var m_collider in target_Colliders)
        {
            var collider_parent = m_collider.transform.parent.name;
            foreach (var m_rigbone in m_base_rigbones)
            {
                if (m_rigbone.name == collider_parent)
                {
                    bool isexist = false;
                    for (int i = 0; i < m_rigbone.childCount; i++)
                    {
                        var child = m_rigbone.GetChild(i);
                        if (child.name == m_collider.transform.name)
                            isexist = true;
                    }
                    if (!isexist)
                    {
                        m_collider.transform.parent = m_rigbone;
                        if (m_IsMagicaCloth)
                        {
                            var magica_collider = m_collider.gameObject.AddComponent<MagicaSphereCollider>();
                            magica_collider.Radius = m_collider.radius;
                            m_collider.enabled = false;
                        }
                    }
                }
            }
        }
    }

    private void CopyMagicaColliders()
    {
        var m_CapsuleColliders = m_DestColliderRoot.GetComponentsInChildren<MagicaCapsuleCollider>();
        var m_SphereColliders = m_DestColliderRoot.GetComponentsInChildren<MagicaSphereCollider>();
        foreach (var m_collider in m_CapsuleColliders)
        {
            var collider_parent = m_collider.transform.parent.name;
            var childs = m_OriginColliderRoot.GetComponentsInChildren<Transform>();
            foreach (var child in childs)
            {
                if (child.name == collider_parent)
                {
                    m_collider.transform.parent = child;
                }
            }
        }
        foreach (var m_collider in m_SphereColliders)
        {
            var collider_parent = m_collider.transform.parent.name;
            var childs = m_OriginColliderRoot.GetComponentsInChildren<Transform>();
            foreach (var child in childs)
            {
                if (child.name == collider_parent)
                {
                    m_collider.transform.parent = child;
                }
            }
        }
    }
}