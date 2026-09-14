# AMSMB2 4.0.3 升级候选

2026-09-14 补充：以下保留升级时的历史记录。原 guest 成功用例实际覆盖 Anonymous；现已新增显式字面空密码模式，最新合同和测试见 [Guest/Anonymous 兼容](guest-authentication.md)。

状态：依赖自动化通过、App 集成验证中、待头显测试；2026-09-07。来源：用户要求从 main 独立升级，不创建 PR。

基于上游 4.0.3；移植 RockVR guest tree connect 与 callback/handle 生命周期保护，适配 SMB2Client、新类型及 Swift 6，保留上游读取、锁和 lease 能力。libsmb2 采用 RockVR 固定提交，选择与排除依据见 Dependencies/libsmb2/tests/moon-client-regression.md。

PR 快速：`swift test --filter CallbackLifetimeTests`（9 项）和 `Dependencies/libsmb2/tests/test-client-lifecycle.sh`。
发布前：`SMB_FIXTURE_PYTHON=<含 impacket 0.13.1 的 python> Scripts/test-read-memory.sh`。三轮各 40 次 4 MiB 读取、48 次交替方向随机偏移读取，按位置校验内容，并验证短读、EOF、缺失文件后恢复、正常断开后残留内存低于基线 +16 MiB、guest 读取。此测试不操作运行中的 App 或 Simulator。

实际视频密集 seek、ISO、断网和真机长期播放由 App 集成验收；本地网络读取不能代替播放器回归。无用户可见文案变化。

选取上游 `497ce6e` 的空密码设置修复，保留本基线的断开错误传播和句柄释放；不整包移植其新底层。fixture 的 guest 在修复前连接超时，修复后连接/读取/正常断开通过。
