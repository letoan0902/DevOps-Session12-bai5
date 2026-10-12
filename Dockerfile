# Stage 1: build file JAR bằng Gradle
FROM gradle:8.10-jdk21 AS build
WORKDIR /home/gradle/project
COPY settings.gradle build.gradle ./
COPY src ./src
RUN gradle bootJar --no-daemon

# Stage 2: image chạy tối giản, không dùng quyền root
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN adduser -D app
COPY --from=build /home/gradle/project/build/libs/app.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
