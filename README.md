# kmod-art-mod

kmod loader 的**卡图包**（替换卡图）格式和相关资料。

- **[SPEC.md](SPEC.md)**：卡图包格式规范（目录结构、`index.json` 字段、路径规则、多包和变体的规则、一致性检查清单）。
- [art-index.schema.json](art-index.schema.json)：`index.json` 的 JSON Schema，可以拿来做校验。
- [examples/example_pack](examples/example_pack)：一个示例 `index.json`。

相关：
- [kmod loader](https://github.com/CCB-TEAM/KMod-Loader-Android)：加载器，`examples/card_art` 是读取卡图包的示例模组，`tools/kmod-art` 是从补丁 pak 生成卡图包的工具。
- [文档](https://kardswalker.github.io/kmod-docs/)

## 一句话版本

```
kmod/art/<包名>/index.json
kmod/art/<包名>/<任意路径>.png
```

```json
[ { "Asset": "/Game/Assets/Textures/Images/Germany/T_pnz_35t", "File": "pnz_35t.png" } ]
```

`Asset` 是被替换贴图的 `/Game/...` 路径（不带扩展名和对象名后缀，比较时不区分大小写），`File` 是包文件夹里 PNG 的相对路径。同一个 `Asset` 可以被多个包替换，玩家在游戏里选用哪个。

## 许可

MIT，见 [LICENSE](LICENSE)。
