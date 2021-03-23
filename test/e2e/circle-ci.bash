#!/bin/bash

set -euxo pipefail

cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function catch {
  cat ./oauth2-client.e2e.log || true
  cat ./login-consent-logout.e2e.log || true
  cat ./hydra.e2e.log || true
}
trap catch ERR

killall hydra || true
killall node || true

# Check if any ports that we need are open already
! nc -zv 127.0.0.1 5000
! nc -zv 127.0.0.1 5001
! nc -zv 127.0.0.1 5002
! nc -zv 127.0.0.1 5003

# Install ORY Hydra
export GO111MODULE=on
if [[ ! -d "../../node_modules/" ]]; then
    (cd ../..; npm ci)
fi
(cd ../../; go build -tags sqlite -o test/e2e/hydra . )

# Install oauth2-client
if [[ ! -d "./oauth2-client/node_modules/" ]]; then
    (cd oauth2-client; npm ci)
fi
(cd oauth2-client; ADMIN_URL=http://127.0.0.1:5001 PUBLIC_URL=http://127.0.0.1:5000 PORT=5003 npm run start > ../oauth2-client.e2e.log 2>&1 &)

# Install consent app
(cd oauth2-client; PORT=5002 HYDRA_ADMIN_URL=http://127.0.0.1:5001 npm run consent > ../login-consent-logout.e2e.log 2>&1 &)

export URLS_SELF_ISSUER=http://127.0.0.1:5000
export URLS_CONSENT=http://127.0.0.1:5002/consent
export URLS_LOGIN=http://127.0.0.1:5002/login
export URLS_LOGOUT=http://127.0.0.1:5002/logout
export SECRETS_SYSTEM=youReallyNeedToChangeThis
export OIDC_SUBJECT_IDENTIFIERS_SUPPORTED_TYPES=public,pairwise
export OIDC_SUBJECT_IDENTIFIERS_PAIRWISE_SALT=youReallyNeedToChangeThis
export SERVE_PUBLIC_CORS_ENABLED=true
export SERVE_PUBLIC_CORS_ALLOWED_METHODS=POST,GET,PUT,DELETE
export SERVE_ADMIN_CORS_ENABLED=true
export SERVE_ADMIN_CORS_ALLOWED_METHODS=POST,GET,PUT,DELETE
export LOG_LEVEL=trace
export LOG_FORMAT=json
export OAUTH2_EXPOSE_INTERNAL_ERRORS=1
export SERVE_PUBLIC_PORT=5000
export SERVE_ADMIN_PORT=5001
export LOG_LEAK_SENSITIVE_VALUES=true
export TEST_DATABASE_SQLITE="sqlite://$(mktemp -d -t ci-XXXXXXXXXX)/e2e.sqlite?_fk=true"

WATCH=no
for i in "$@"
do
case $i in
    --watch)
    WATCH=yes
    shift # past argument=value
    ;;
    *)
    case "$i" in
            memory)
               ./hydra migrate sql --yes $TEST_DATABASE_SQLITE > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_SQLITE \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=false
                ;;

            memory-jwt)
                ./hydra migrate sql --yes $TEST_DATABASE_SQLITE > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_SQLITE \
                    STRATEGIES_ACCESS_TOKEN=jwt \
                    OIDC_SUBJECT_IDENTIFIERS_SUPPORTED_TYPES=public \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=true
                ;;

            postgres)
                ./hydra migrate sql --yes $TEST_DATABASE_POSTGRESQL > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_POSTGRESQL \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=false
                ;;

            postgres-jwt)
                ./hydra migrate sql --yes $TEST_DATABASE_POSTGRESQL > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_POSTGRESQL \
                    STRATEGIES_ACCESS_TOKEN=jwt \
                    OIDC_SUBJECT_IDENTIFIERS_SUPPORTED_TYPES=public \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=true
                ;;

            mysql)
                ./hydra migrate sql --yes $TEST_DATABASE_MYSQL > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_MYSQL \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=false
                ;;

            mysql-jwt)
                ./hydra migrate sql --yes $TEST_DATABASE_MYSQL > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_MYSQL \
                    STRATEGIES_ACCESS_TOKEN=jwt \
                    OIDC_SUBJECT_IDENTIFIERS_SUPPORTED_TYPES=public \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=true
                ;;

            cockroach)
                ./hydra migrate sql --yes $TEST_DATABASE_COCKROACHDB > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_COCKROACHDB \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=false
                ;;

            cockroach-jwt)
                ./hydra migrate sql --yes $TEST_DATABASE_COCKROACHDB > ./hydra-migrate.e2e.log 2>&1
                DSN=$TEST_DATABASE_COCKROACHDB \
                    STRATEGIES_ACCESS_TOKEN=jwt \
                    OIDC_SUBJECT_IDENTIFIERS_SUPPORTED_TYPES=public \
                    ./hydra serve all --dangerous-force-http --sqa-opt-out > ./hydra.e2e.log 2>&1 &
                export CYPRESS_jwt_enabled=true
                ;;

            *)
                echo $"Usage: $0 {memory|postgres|mysql|cockroach|memory-jwt|postgres-jwt|mysql-jwt|cockroach-jwt} [--watch]"
                exit 1
    esac
    ;;
esac
done

npm run wait-on -- -l -t 300000 \
  --interval 1000 -s 1 -d 1000 \
  http-get://localhost:5000/health/ready http-get://localhost:5001/health/ready http-get://localhost:5002/ http-get://localhost:5003/oauth2/callback

if [[ $WATCH = "yes" ]]; then
    (cd ../..; npm run test:watch)
else
    (cd ../..; npm run test)
fi

kill %1 || true # This is oauth2-client
kill %2 || true # This is the login-consent-logout
kill %3 || true # This is the hydra

rm ./oauth2-client.e2e.log
rm ./login-consent-logout.e2e.log
rm ./hydra.e2e.log

exit 0
