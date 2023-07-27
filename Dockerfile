ARG POSTGRES_VERSION=15
FROM docker.io/postgres:${POSTGRES_VERSION}

RUN mkdir /pg-iam
COPY install.sh /pg-iam/install.sh
COPY ./src/ /pg-iam/src/

RUN echo "#!/bin/bash\n\
export SUPERUSER=\"\$POSTGRES_USER\"\n\
export DBOWNER=\"\$POSTGRES_USER\"\n\
export DBNAME=\"\$POSTGRES_DB\"\n\
yes | /pg-iam/install.sh --setup --force" > /docker-entrypoint-initdb.d/pg-iam.sh
RUN chmod +x /docker-entrypoint-initdb.d/pg-iam.sh
