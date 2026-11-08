# plus-ui (RuoYi-Cloud-Plus 前端) 运行镜像
#
# 套路与 ruoyi-mini/ruoyi_web/Dockerfile 一致：
#   静态资源由 nginx 托管 + 覆盖 nginx.conf 实现 API 反代。
# 关键差异：
#   1) 基础镜像改用多架构 nginx:1.27-alpine（x86 / ARM 通吃）；
#      ruoyi-mini 用的是 arm64v8/nginx（仅 ARM），按需替换即可。
#   2) 这里只负责"打包"，前端构建（npm run build 产出 dist/）
#      由 CI 在 docker build 之前完成，dist/ 必须已存在于构建上下文。
#
# 【放哪】本文件应放在前端仓库（RuoYi-Cloud-Plus-UI）根目录，
#        或把构建上下文指向该仓库根目录，否则 COPY dist/ 会失败。
#        仓库里若无 dist/，先跑 `npm run build`（产出默认在 dist/）。

FROM nginx:1.27-alpine
LABEL maintainer="ruoyi-cloud-plus"

# 1) 覆盖 nginx 配置（含 /prod-api -> 网关 Service、/snail-ai/ -> snailai Service 的反代）
COPY nginx.conf /etc/nginx/nginx.conf

# 2) 拷贝前端构建产物（由 CI 的 npm run build 产出）
COPY dist/ /usr/share/nginx/html/

# 3) 权限（nginx.conf 里 user nginx; 需要对 html 目录可读，防 403）
RUN chown -R nginx:nginx /usr/share/nginx/html \
 && chmod -R 755 /usr/share/nginx/html

EXPOSE 80
# 官方推荐前台运行方式，适合容器
CMD ["nginx", "-g", "daemon off;"]
