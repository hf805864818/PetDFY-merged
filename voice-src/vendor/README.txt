把库放在这里，Makefile 会自动用 -I / -L 指向：

opus/    include/opus/opus.h        lib/libopus.a        (opus 1.6.1)
openssl/ include/openssl/*.h        lib/libcrypto.a      (OpenSSL 3.x，需 EC/ECDH)
miniz/   miniz.c  miniz.h                                (单文件，public domain)

原始 petdfy-voice 把这三个库静态编进可执行文件（__TEXT 里能看到
opus-1.6.1 的 assert 路径与 ossl_*/mz_* 符号），重建工程改为链接同版本库。
