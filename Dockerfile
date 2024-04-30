# 第一阶段：使用标准 Nginx 镜像作为基础镜像，用于构建 Brotli 模块
FROM nginx:1.25.4 as builder

# 安装必要的构建工具和库
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    build-essential \
    libpcre3-dev \
    zlib1g-dev \
    libssl-dev \
    wget \
    git \
    cmake \
    autoconf \
    libtool

# 克隆 ngx_brotli 和 Brotli 源代码，编译 Brotli 库
RUN git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli /usr/src/ngx_brotli \
    && cd /usr/src/ngx_brotli/deps/brotli \
    && mkdir out && cd out \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF .. \
    && cmake --build . --config Release --target brotlienc \
    && make install

# 下载并准备 Nginx 源码
RUN wget https://nginx.org/download/nginx-1.25.4.tar.gz -O /tmp/nginx.tar.gz \
    && tar -zxvf /tmp/nginx.tar.gz -C /usr/src/ \
    && mv /usr/src/nginx-1.25.4 /usr/src/nginx

# 编译 Nginx 与 Brotli 模块
RUN cd /usr/src/nginx \
    && ./configure --with-compat --add-dynamic-module=/usr/src/ngx_brotli \
    && make modules

# 第二阶段：使用一个干净的 Nginx 镜像
FROM nginx:1.25.4

# 从 builder 阶段复制编译好的模块到适当位置
COPY --from=builder /usr/src/nginx/objs/ngx_http_brotli_filter_module.so /usr/lib/nginx/modules/
COPY --from=builder /usr/src/nginx/objs/ngx_http_brotli_static_module.so /usr/lib/nginx/modules/

# 在 Nginx 配置文件中加载 Brotli 模块
RUN mkdir -p /etc/nginx/modules-enabled \
    && echo 'load_module modules/ngx_http_brotli_filter_module.so;' > /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf \
    && echo 'load_module modules/ngx_http_brotli_static_module.so;' > /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf

# 覆盖 nginx.conf
COPY ./nginx.conf /etc/nginx/nginx.conf
