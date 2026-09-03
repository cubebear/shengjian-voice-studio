# 第三方许可证与来源

本文件用于说明分发关系，不替代下面各组件的完整许可文本。声笺的 MIT 许可证仅覆盖项目原创部分，不将第三方代码或模型重新许可。

| 组件 | 来源 / 版本 | 许可证及随附位置 |
|---|---|---|
| 声笺界面、Swift 封装、构建脚本 | 本仓库 | [MIT](LICENSE)，Copyright (c) 2026 ShengJian Studio contributors |
| qwen3-tts C 引擎 | [上游](https://github.com/gabriele-mastrapasqua/qwen3-tts)，`f1b6865713d12a2a2365282fc02e19a5a384a565` | [MIT](Vendor/qwen3-tts/LICENSE)，Copyright (c) 2025 Gabriele Mastrapasqua |
| ingot | [上游](https://github.com/mynah-org/ingot)，随上述引擎快照固定 | [MIT](Vendor/qwen3-tts/third_party/ingot/LICENSE)，Copyright (c) 2026 Gabriele Mastrapasqua |
| llama.cpp / ggml 派生表 | ingot 的 `src/iq_tables.inc` 从 llama.cpp 的 gguf 包提取；原注释保留 | [MIT](Licenses/llama.cpp-MIT.txt)，Copyright (c) 2023-2026 The ggml authors；[上游许可](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE) |
| LZ4 | 引擎随附 `vendor/lz4.c`、`vendor/lz4.h` | BSD-2-Clause，完整文本保留在 [lz4.h](Vendor/qwen3-tts/vendor/lz4.h) 开头，Copyright (c) 2011–2023 Yann Collet |
| KleidiAI 子集 | [Arm 上游](https://github.com/ARM-software/kleidiai)，原 NOTICE 记录版本 `495f652` | [Apache-2.0](Vendor/qwen3-tts/third_party/kleidiai/Apache-2.0.txt) 与 [NOTICE](Vendor/qwen3-tts/third_party/kleidiai/NOTICE.md)，Arm Limited and/or its affiliates；保留逐文件声明 |

本仓库提供引擎的源代码子集，省略上游训练素材、演示音频、Git 历史和编译产物。`PINNED_REVISION` 记录引擎来源版本；构建脚本覆盖 Intel/macOS 编译参数。KleidiAI 的 ARM 内核保留在源代码快照中，不参与本版 Intel CPU 构建。

`Vendor/qwen3-tts/third_party/ingot/tests/fixtures/` 中的小型 `.bin` / `.ref` 是上游量化格式测试数据，不是用户声音档案，也不是可推理的模型权重。`Tests/Fixtures/modelscope-base.json` 是公开模型文件元数据，不含账号凭据。

应用安装包 `Contents/Resources/Licenses/` 包含声笺、qwen3-tts、ingot、llama.cpp、LZ4 的许可文本，以及 KleidiAI 许可与声明副本。该目录中的本文件链接按源码仓库相对路径编写；在安装包内可直接阅读旁边的文本副本。

## 模型另行下载

Qwen 官方的 Qwen3-TTS 模型由用户从 ModelScope 或 Hugging Face 下载，适用模型发布方的 Apache-2.0 许可证。本仓库和应用发行包**不包含模型权重**。以 [Qwen 官方项目](https://github.com/QwenLM/Qwen3-TTS) 和各模型仓库的 LICENSE / 模型卡为准。

保存的 `.qvoice` 可能含有源模型的一部分权重；如另行分发，应保留该模型适用的许可、声明及所需修改说明，并确保参考声音已有分享授权。声笺的许可证不授予模型发布方商标或任何第三方身份使用权。
