# 声笺 0.1.0 · 实验版

[English](https://github.com/cubebear/shengjian-voice-studio/blob/main/docs/RELEASE_NOTES.md) | **简体中文**

[下载本版本](https://github.com/cubebear/shengjian-voice-studio/releases/tag/v0.1.0) · [中文项目说明](https://github.com/cubebear/shengjian-voice-studio/blob/main/README.zh-CN.md) · [完整使用教程](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

Intel Mac 本地语音工作室，提供声音克隆、文稿导入、分段生成、音频调整及双来源模型管理。下载和准备模型后可在本地生成，不需要安装 Python、Docker 或 Homebrew。

## 0.1.0 包含什么

这是首个实验版应用发行，包含可直接解压运行的安装包，不只是源码快照。

- 原生 Intel Mac 图形界面，内置 AVX2 与兼容引擎，自动准备和修复私有运行环境。
- 从本人或获得授权的录音克隆声音，并保存、复用声音档案。
- TXT、Markdown、RTF 文稿导入，分段生成、单段重生成及 WAV 导出。
- 音频裁剪、增益、归一化、淡入淡出、变速与变调。
- 魔搭或 Hugging Face 模型下载，支持版本固定、断点续传、大小及哈希校验，也可导入现有完整模型目录。

## 下载文件

| 文件 | 用途 |
|---|---|
| [ShengJian-Intel-0.1.zip](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/ShengJian-Intel-0.1.zip) | Intel Mac 应用，普通用户下载这个 |
| [ShengJian-Source-0.1.zip](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/ShengJian-Source-0.1.zip) | 完整源码包，包含推理引擎源码及许可声明 |
| [SHA256SUMS.txt](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/SHA256SUMS.txt) | 下载文件的 SHA-256 校验清单 |
| [USER_GUIDE.zh-CN.md](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/USER_GUIDE.zh-CN.md) | 中文使用教程 |
| [VERIFICATION.zh-CN.md](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/VERIFICATION.zh-CN.md) | 中文验证报告 |
| [screenshot.png](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/screenshot.png) | 应用界面预览 |

**附件不包含模型权重。** 应用压缩包较小，是因为只包含界面和原生运行时；模型需要另行下载或导入。建议首先尝试 0.6B Base，其模型文件约 2.52GB。

## 安装

1. 在上表下载 `ShengJian-Intel-0.1.zip` 和 `SHA256SUMS.txt`，先核对应用压缩包的 SHA-256。
2. 解压，将 `ShengJian-Intel.app` 拖入“应用程序”，然后打开。
3. 等待“本地引擎就绪”。在“模型管理”选择魔搭或 Hugging Face，下载 **0.6B Base**；也可导入受支持的完整模型目录。
4. 选择本人或明确授权的参考录音，填写录音对应文字，先生成一句短文，再尝试长文。

应用只有临时签名，没有 Developer ID 签名或公证。仅在确认来源并核对哈希后，通过系统对单个应用的允许入口打开；不要全局关闭 Gatekeeper。

## 请先了解

- 编译目标为 macOS 10.15 / x86_64，尚未在 2019 Mac Pro 或旧 macOS 实测。
- 已完成 Rosetta 下的 0.6B Base 真实生成、26 项核心测试、两种引擎数值自检及运行时修复测试。
- 参考音由电脑合成，未验证本人音色的克隆相似度；CPU 性能不能按本次 Rosetta 结果推算。
- 1.7B、CustomVoice、VoiceDesign 及实验控制没有全部完成真实生成验收；Hugging Face 实际下载仍需目标网络验证。
- 仅提供推理，不包括训练、GPU 加速或实时流式播放。

请仅使用本人或明确授权的声音，对外分享时标注合成性质。源码及发行包不包含个人录音、声音档案或模型权重。保留了第三方许可和来源声明。

详见仓库 README、使用说明、验证报告和第三方声明。

安装包和源码附件对应原始 `v0.1.0` 标签。本次完善发行说明不改动程序、校验文件或版本标签；最新中英文文档请以上方仓库链接为准。
