#!/bin/bash

: ${VERSION:="2.4.0"}
docker build --build-arg VERSION=$VERSION -t quay.io/kaszpir/opentsdb:$VERSION .

docker push quay.io/kaszpir/opentsdb:$VERSION
