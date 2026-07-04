# ==============================================================================
# Stage 1: base (Requirement 1 & 2)
# ==============================================================================
FROM ubuntu:26.04 AS base

# 設定非互動模式與時區 (預設為台灣時區)
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei

# 1. 更新並安裝 tzdata 以設定 UTC 以外的當地時區
# 2. 清理 apt cache 減少 Image 體積
RUN apt-get update && apt-get install -y tzdata \
    && ln -fs /usr/share/zoneinfo/$TZ /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && rm -rf /var/lib/apt/lists/*

# 建立固定的 UID/GID 與 Non-root 帳號 (避免掛載 Volume 時權限錯亂)
ARG USERNAME=myuser
ARG UID=1000
ARG GID=1000

# 先嘗試刪除佔用的預設使用者 (ubuntu)，如果不存在則忽略錯誤 (|| true)
RUN (userdel -r ubuntu || true) \
    && groupadd -g ${GID} $USERNAME \
    && useradd -u ${UID} -g ${GID} -m -s /bin/bash $USERNAME

# ==============================================================================
# Stage 2: common_pkg_provider (Requirement 3 - APT & PIP)
# ==============================================================================
FROM base AS common_pkg_provider

# 安裝 Core CLI Tools 與 Python/編譯環境
RUN apt-get update && apt-get install -y \
    vim git curl wget ca-certificates \
    build-essential \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 建立 python 指向 python3 的 symlink
RUN ln -s /usr/bin/python3 /usr/bin/python

# 處理 PEP 668 問題：在 Container 中直接加上 --break-system-packages 旗標
RUN pip install --break-system-packages pytest setuptools wheel

# ==============================================================================
# Stage 3: verilator_provider (Requirement 3 - Build from Source)
# ==============================================================================
FROM common_pkg_provider AS verilator_provider

# 安裝 Verilator 需要的額外編譯相依套件
RUN apt-get update && apt-get install -y flex bison autoconf help2man perl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/verilator-build
# 從官方 GitHub 下載並編譯，將成品安裝至獨立目錄 /opt/verilator
RUN git clone https://github.com/verilator/verilator . \
    && git checkout v5.024 \
    && autoconf \
    && ./configure --prefix=/opt/verilator \
    && make -j$(nproc) \
    && make install

# ==============================================================================
# Stage 4: systemc_provider (Requirement 3 - Build from Source)
# ==============================================================================
FROM common_pkg_provider AS systemc_provider

# 透過 TARGETARCH 變數捕捉 Docker buildx 傳入的 CPU 架構資訊 (amd64 / arm64)
ARG TARGETARCH

WORKDIR /tmp/systemc-build
# 下載 Accellera SystemC 3.0.2
RUN wget https://github.com/accellera-official/systemc/archive/refs/tags/3.0.2.tar.gz \
    && tar -xzf 3.0.2.tar.gz

WORKDIR /tmp/systemc-build/systemc-3.0.2/objdir
# 設定 CXXFLAGS 將標準設為 C++17，並將 SystemC 安裝至獨立目錄 /opt/systemc
RUN ../configure --prefix=/opt/systemc CXXFLAGS="-std=c++17" \
    && make -j$(nproc) \
    && make install

# ==============================================================================
# Stage 5: release (最終成品)
# ==============================================================================
# 繼承 common_pkg_provider，這樣就能直接擁有 apt/pip 裝好的所有工具！
FROM common_pkg_provider AS release

# 利用 Multi-stage build 的優勢：只複製乾淨的編譯成品，不帶走編譯過程產生的垃圾檔案
COPY --from=verilator_provider /opt/verilator /opt/verilator
COPY --from=systemc_provider /opt/systemc /opt/systemc

# 設定環境變數
# ENV VERILATOR_ROOT=/opt/verilator
ENV SYSTEMC_HOME=/opt/systemc
# 將 Verilator 執行檔加入 PATH
ENV PATH=/opt/verilator/bin:$PATH

# 切換為 Non-root 使用者運行
USER $USERNAME
WORKDIR /home/$USERNAME

# 預設執行 Bash
CMD ["/bin/bash"]