# SYNOPSYS

Конечная цель этого репозитория - попробовать работу Future::AsyncAwait совместно с DBD::Pg и IO::Async. Эдакий аналог Mojo::Pg с IO::Async в качестве цикла событий ввода/вывода и Future вместо Mojo::Promise.

За выходные реализовать её, впрочем, не получилось. Так что пока это обычное Plack приложение на основе Net::Async::HTTP::Server.