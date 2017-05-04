#!/bin/sh

set -e

# Default if not supplied - same as weave net default
IPALLOC_RANGE=${IPALLOC_RANGE:-10.32.0.0/12}
HTTP_ADDR=${WEAVE_HTTP_ADDR:-127.0.0.1:6784}
STATUS_ADDR=${WEAVE_STATUS_ADDR:-0.0.0.0:6782}
HOST_ROOT=${HOST_ROOT:-/host}
WEAVE_DIR="/host/var/lib/weave"

mkdir $WEAVE_DIR || true

echo "Starting launch.sh"

# Check if the IP range overlaps anything existing on the host
/usr/bin/weaveutil netcheck $IPALLOC_RANGE weave

# We need to get a list of Swarm nodes which might run the net-plugin:
# - In the case of missing restart.sentinel, we assume that net-plugin has started
#   for the first time via the docker-plugin cmd. So it's safe to request docker.sock.
# - If restart.sentinel present, let weaver restore from it as docker.sock is not
#   available to any plugin in general (https://github.com/moby/moby/issues/32815).

PEERS=
IPALLOC_INIT=
if [ ! -f "/restart.sentinel" ]; then
    STATUS=0
    /usr/bin/weaveutil is-swarm-manager 2>/dev/null || STATUS=$?
    if [ $STATUS -eq 0 ]; then
        IS_SWARM_MANAGER=1
    elif [ $STATUS -eq 20 ]; then
        echo "Host swarm is not \"active\"; exiting." >&2
        exit 1
    fi

    SWARM_MANAGER_PEERS=$(/usr/bin/weaveutil swarm-manager-peers)

    if [ -z "$IPALLOC_INIT" ]; then
        IPALLOC_INIT="observer"
        if [ "$IS_SWARM_MANAGER" == "1" ]; then
            IPALLOC_INIT="consensus=$(echo $SWARM_MANAGER_PEERS | wc -l)"
        fi
    fi

    PEERS=$(echo $SWARM_MANAGER_PEERS | tr '\n' ' ')
    IPALLOC_INIT="--ipalloc-init $IPALLOC_INIT"
fi

router_bridge_opts() {
    echo --datapath=datapath
    [ -z "$WEAVE_MTU" ] || echo --mtu "$WEAVE_MTU"
    [ -z "$WEAVE_NO_FASTDP" ] || echo --no-fastdp
}

multicast_opt() {
    [ -z "$WEAVE_MULTICAST" ] || echo "--plugin-v2-multicast"
}

exec /home/weave/weaver $EXTRA_ARGS --port=6783 $(router_bridge_opts) \
    --host-root=/host \
    --proc-path=/host/proc \
    --http-addr=$HTTP_ADDR --status-addr=$STATUS_ADDR \
    --no-dns \
    --ipalloc-range=$IPALLOC_RANGE \
    $IPALLOC_INIT \
    --nickname "$(hostname)" \
    --log-level=debug \
    --db-prefix="$WEAVE_DIR/weave" \
    --plugin-v2 \
    $(multicast_opt) \
    --plugin-mesh-socket='' \
    --docker-api='' \
    $PEERS
