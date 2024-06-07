##############################
#    docker build stage 1    #
##############################
## arch: x86_64
# ARG IMAGE_MVN=maven:3.8-openjdk-17
ARG IMAGE_MVN=maven:3.8-jdk-8
ARG IMAGE_JDK=openjdk:8
# ARG IMAGE_JDK=amazoncorretto:8
# ARG IMAGE_JDK=amazoncorretto:11
# ARG IMAGE_JDK=amazoncorretto:17
## arch: arm64
# ARG IMAGE_MVN=arm64v8/maven:3.6-jdk-8
# ARG IMAGE_JDK=arm64v8/openjdk:8
FROM ${IMAGE_MVN} AS builder
ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=off
ARG MVN_COPY_YAML=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
WORKDIR /src
RUN --mount=type=cache,target=/var/maven/.m2 --mount=type=bind,target=.,rw if [ ! -f root/opt/build.sh ]; then curl -fLo root/opt/build.sh $BUILD_URL; fi; bash root/opt/build.sh


##############################
#    docker build stage 2    #
##############################
FROM ${IMAGE_JDK}
ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG INSTALL_LIBREOFFICE=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV TZ=$TZ
WORKDIR /app
COPY --from=builder /jars/ .
COPY ./root/ /
RUN set -xe; \
    if [ ! -f /opt/build.sh ]; then curl -fLo /opt/build.sh $BUILD_URL; else :; fi; \
    if [ -f /opt/build.sh ]; then bash /opt/build.sh; else :; fi
#USER 1000
EXPOSE 8080 8081 8082
# volume /data
CMD ["bash", "/opt/run0.sh"]
