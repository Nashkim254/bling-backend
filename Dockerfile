FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

RUN dart pub get --offline

EXPOSE 8000

CMD ["dart", "run", "bin/server.dart"]
