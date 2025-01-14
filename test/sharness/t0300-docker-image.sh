#!/usr/bin/env bash
#
# Copyright (c) 2015 Christian Couder
# MIT Licensed; see the LICENSE file in this repository.
#

test_description="Test docker image"

. lib/test-lib.sh

# if in travis CI on OSX, docker is not available
if ! test_have_prereq DOCKER; then
  skip_all='skipping docker tests, docker not available'

  test_done
fi

test_expect_success "'docker --version' works" '
  docker --version >actual
'

test_expect_success "'docker --version' output looks good" '
  egrep "^Docker version" actual
'

TEST_TRASH_DIR=$(pwd)
TEST_SCRIPTS_DIR=$(dirname "$TEST_TRASH_DIR")
TEST_TESTS_DIR=$(dirname "$TEST_SCRIPTS_DIR")
APP_ROOT_DIR=$(dirname "$TEST_TESTS_DIR")

test_expect_success "docker image build succeeds" '
  docker_build "$TEST_TESTS_DIR/../Dockerfile" "$APP_ROOT_DIR" >build-actual ||
  test_fsh echo "TEST_TESTS_DIR: $TEST_TESTS_DIR" ||
  test_fsh echo "APP_ROOT_DIR : $APP_ROOT_DIR" ||
  test_fsh cat build-actual
'

test_expect_success "docker image build output looks good" '
  SUCCESS_LINE=$(egrep "^Successfully built" build-actual) &&
  IMAGE_ID=$(expr "$SUCCESS_LINE" : "^Successfully built \(.*\)") ||
  test_fsh cat build-actual
'

test_expect_success "docker image runs" '
  DOC_ID=$(docker run -d -p 127.0.0.1:5001:5001 -p 127.0.0.1:8080:8080 "$IMAGE_ID")
'

test_expect_success "docker container gateway is up" '
  pollEndpoint -host=/ip4/127.0.0.1/tcp/8080 -http-url http://localhost:8080/api/v0/version -v -tries 30 -tout 1s
'

test_expect_success "docker container API is up" '
  pollEndpoint -host=/ip4/127.0.0.1/tcp/5001 -http-url http://localhost:5001/version -v -tries 30 -tout 1s
'

test_expect_success "simple ipfs add/cat can be run in docker container" '
  expected="Hello Worlds" &&
  HASH=$(docker_exec "$DOC_ID" "echo $(cat expected) | ipfs add | cut -d' ' -f2") &&
  docker_exec "$DOC_ID" "ipfs cat $HASH" >actual &&
  test_cmp expected actual
'

read testcode <<EOF
  pollEndpoint -host=/ip4/127.0.0.1/tcp/5001 -http-url http://localhost:5001/version -http-out | grep Commit | cut -d" " -f2 >actual ; \
  test -s actual ; \
  docker exec -i "$DOC_ID" ipfs version --enc json \
    | sed 's/^.*"Commit":"\\\([^"]*\\\)".*$/\\\1/g' >expected ; \
  test -s expected ; \
  test_cmp expected actual
EOF
test_expect_success "version CurrentCommit is set" "$testcode"

test_expect_success "stop docker container" '
  docker_stop "$DOC_ID"
'

test_done

