# 声笺 0.1.0 · 实验版

[English](https://github.com/cubebear/shengjian-voice-studio/blob/main/docs/RELEASE_NOTES.md) | **简体中文**

[下载本版本](https://github.com/cubebear/shengjian-voice-studio/releases/tag/v0.1.0) · [中文项目说明](https://github.com/cubebear/shengjian-voice-studio/blob/main/README.zh-CN.md) · [完整使用教程](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

Intel Mac 本地语音工作室，提供声音克隆、文稿导入、分段生成、音频调整及双来源模型管理。下载和准备模型后可在本地生成，不需要安装 Python、Docker 或 Homebrew。

## 安装

下载 `ShengJian-Intel-0.1.zip`，核对同页 `SHA256SUMS.txt`，解压后打开应用。模型不随安装包分发；首次试用推荐在“模型管理”选择魔搭或 Hugging Face 下载 0.6B Base。

应用只有临时签名，没有 Developer ID 签名或公证。仅在确认来源并核对哈希后，通过系统对单个应用的允许入口打开；不要全局关闭 Gatekeeper。

## 请先了解

- 编译目标为 macOS 10.15 / x86_64，尚未在 2019 Mac Pro 或旧 macOS 实测。
- 已完成 Rosetta 下的 0.6B Base 真实生成、26 项核心测试、两种引擎数值自检及运行时修复测试。
- 参考音由电脑合成，未验证本人音色的克隆相似度；CPU 性能不能按本次 Rosetta 结果推算。
- 1.7B、CustomVoice、VoiceDesign 及实验控制没有全部完成真实生成验收；Hugging Face 实际下载仍需目标网络验证。
- 仅提供推理，不包括训练、GPU 加速或实时流式播放。

请仅使用本人或明确授权的声音，对外分享时标注合成性质。源码及发行包不包含个人录音、声音档案或模型权重。保留了第三方许可和来源声明。

详见仓库 README、使用说明、验证报告和第三方声明。

本次仅调整在线文档的语言与导航。原有 0.1.0 安装包、源码附件、校验文件和版本标签保持不变；最新中英文说明请以上方仓库链接为准。
