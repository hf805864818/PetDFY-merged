# 程序 / 素材分离构建

- build.077 只包含程序、设置页、着色器和语音服务，不包含 originals/、live/。
- 素材独立导入到 PetDFY.bundle/originals/ 与 PetDFY.bundle/live/model.json。
- 未导入素材时日志为 ensureWindow FAIL: missing live/model.json。
- make assets 是完整包构建方式；分离包不要执行它。
