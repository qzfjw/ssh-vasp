# Materials Project 结构获取

仅当用户的 VASP 工作流需要获取初始晶体结构、材料属性或候选材料时使用本参考。优先使用官方 `mp-api` Python 客户端，不在 Skill 中维护易过时的原始 REST 端点表。

## 凭据规则

- API Key 保存在本 Skill 的 `config/local.psd1`。
- 不要直接读取或输出配置文件内容，只通过 `scripts/load_mp_config.ps1` 设置当前 PowerShell 进程的 `MP_API_KEY`。
- 不要把 Key 回显到聊天、命令日志、Python 文件或生成结果中。
- 配置文件和加载脚本必须保留在本机，不上传到超算。

加载配置：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/load_mp_config.ps1"
```

加载脚本与使用 `mp-api` 的 Python 命令必须位于同一次 PowerShell 调用中，因为新的 shell 进程不会继承上一进程临时设置的环境变量。

需要更换 Key 时，只修改：

```text
%USERPROFILE%\.codex\skills\fang_ssh_skill\config\local.psd1
```

保持以下结构，不要更改字段名：

```powershell
@{
    MaterialsProjectApiKey = '<replace-locally>'
}
```

## 安装客户端

只有用户需要并允许安装依赖时才执行：

```powershell
python -m pip install --upgrade mp-api
```

## 下载结构

先加载配置，然后在同一次 PowerShell 调用中运行 Python 脚本：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/load_mp_config.ps1"
python ./download_structure.py
```

`download_structure.py` 内容：

```python
from mp_api.client import MPRester

material_id = "mp-149"

with MPRester() as mpr:
    structure = mpr.get_structure_by_material_id(material_id)

structure.to(filename="POSCAR", fmt="poscar")
```

生成后检查 POSCAR 的化学式、目标相、空间群、晶格、原子数、元素顺序和周期性最近邻距离，再为其选择匹配的 POTCAR。Materials Project 不提供用户可直接用于 VASP 计算的授权 POTCAR。

同一化学式可能返回多个多型、层数、磁性状态或不同计算来源。不得仅按化学式、带隙或最低 `energy_above_hull` 自动选择；先展示候选材料 ID、空间群、原子数和能量信息，再匹配用户指定的相。若进行晶胞基矢变换，记录原材料 ID、原空间群和变换矩阵或坐标规则。

## 搜索候选材料

```python
from mp_api.client import MPRester

with MPRester() as mpr:
    documents = mpr.materials.summary.search(
        chemsys="Fe-Te-Pd",
        fields=["material_id", "formula_pretty", "symmetry", "structure", "energy_above_hull", "band_gap"],
    )

for document in documents:
    print(
        document.material_id,
        document.formula_pretty,
        document.symmetry.symbol,
        len(document.structure),
        document.energy_above_hull,
        document.band_gap,
    )
```

客户端接口可能随版本演进。出现参数或字段错误时，查询当前官方 Materials Project 文档和已安装 `mp-api` 版本，而不是猜测 URL。
