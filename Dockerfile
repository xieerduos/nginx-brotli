ARG NGINX_VERSION=1.31.1

# 第一阶段：使用标准 Nginx 镜像作为基础镜像，用于构建 Brotli 模块
FROM nginx:${NGINX_VERSION} AS builder

ARG NGINX_VERSION

# 安装必要的构建工具和库
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    autoconf \
    libtool \
    libpcre2-dev \
    libssl-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 克隆 ngx_brotli 和 Brotli 源代码，编译 Brotli 库
RUN git clone --depth=1 --recurse-submodules -j8 https://github.com/google/ngx_brotli /usr/src/ngx_brotli \
    && cd /usr/src/ngx_brotli/deps/brotli \
    && mkdir out && cd out \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF .. \
    && cmake --build . --config Release --target brotlienc \
    && make install

# 下载并准备 Nginx 源码
RUN curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o /tmp/nginx.tar.gz \
    && tar -zxvf /tmp/nginx.tar.gz -C /usr/src/ \
    && mv "/usr/src/nginx-${NGINX_VERSION}" /usr/src/nginx

# 编译 Nginx 与 Brotli 模块
RUN cd /usr/src/nginx \
    && ./configure --with-compat --add-dynamic-module=/usr/src/ngx_brotli \
    && make modules

# 第二阶段：使用一个干净的 Nginx 镜像
FROM nginx:${NGINX_VERSION}

ARG NGINX_VERSION
LABEL org.opencontainers.image.title="nginx-brotli" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.source="https://github.com/xieerduos/nginx-brotli" \
      org.opencontainers.image.description="Official NGINX image with google ngx_brotli dynamic modules"

# 从 builder 阶段复制编译好的模块到适当位置
COPY --from=builder /usr/src/nginx/objs/ngx_http_brotli_filter_module.so /usr/lib/nginx/modules/
COPY --from=builder /usr/src/nginx/objs/ngx_http_brotli_static_module.so /usr/lib/nginx/modules/

# 在 Nginx 配置文件中加载 Brotli 模块
RUN mkdir -p /etc/nginx/modules-enabled \
    && echo 'load_module modules/ngx_http_brotli_filter_module.so;' > /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf \
    && echo 'load_module modules/ngx_http_brotli_static_module.so;' > /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf

# 覆盖 nginx.conf
COPY ./nginx.conf /etc/nginx/nginx.conf
