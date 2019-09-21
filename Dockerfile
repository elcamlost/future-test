FROM       perl:5.28.2
MAINTAINER Ilya "elcamlost" Rassadin <elcamlost@gmail.com>


RUN   apt-get update -y \
    && apt-get -y install build-essential libpq-dev netcat \
    && cpanm --notest --force Carton \
    && cpanm --notest --force Bundle::Camelcade \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /root/.cpanm/

COPY  ./cpanfile* /app/

WORKDIR /app
ENV     RUN_MODE="development"
ENV PATH="/app/local/bin:${PATH}"
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
EXPOSE  5000
CMD     [ "carton", "install" ]
