#!/bin/bash

OT_USER=testuser@example.com
OT_PASSWORD=secret

OT_MAIN_URL=admdemo.opentalk.eu
OT_KEYCLOAK_URL=accounts.${OT_MAIN_URL}
OT_CONTROLLER_URL=controller.${OT_MAIN_URL}
OT_PROTO=https://

# if the next two values are not known you can read them from the URL when
# logging in:
# https://accounts.admdemo.opentalk.eu/auth/realms/admdemo/login-actions/
# authenticate?session_code=<session>&client_id=openid_admdemo_test_public&..
OT_CLIENT_ID=openid_admdemo_test_public
OT_REALM_NAME=admdemo

DEFAULT_EXPIRATION_HOURS=24
GET_MAX_EVENTS=30

# you probably want to store the credentials and other variables
# in a configuration file
OT_CONFIG=~/.opentalk_api.rc
if [ -r "$OT_CONFIG" ]; then
    . "$OT_CONFIG"
fi

# nothing to change below
usage () {
    SCRIPT=$(basename $0)
echo "$SCRIPT -c              create event (--create)
$SCRIPT -l              list events (--list-events)
$SCRIPT -r              list rooms (--rooms)
$SCRIPT -i <room id>    show information for room (--info)
"
    exit 0
}

ot_login () {
    OT_TOKEN=$(curl -s -d 'client_id='${OT_CLIENT_ID}'' \
                    -d 'username='${OT_USER}'' \
                    -d 'password='${OT_PASSWORD}'' \
                    -d 'scope=openid' \
                    -d 'grant_type=password' \
                    'https://'${OT_KEYCLOAK_URL}'/auth/realms/'${OT_REALM_NAME}'/protocol/openid-connect/token')

        if [ "$(echo "$OT_TOKEN" | grep \"access_token\":)" = "" ]; then
            echo "- something went wrong getting token:"
            echo "$OT_TOKEN"
            exit 1
        else
            OT_TOKEN="$(echo "$OT_TOKEN" | jq -r .access_token)"
        fi

        SESSION=$(curl -s -X POST 'https://'${OT_CONTROLLER_URL}'/v1/auth/login' \
                -H 'Content-Type: application/json' \
                -d '{ "id_token": "'${OT_TOKEN}'" }')
}

ot_create_room () {
    E_ROOM_ID=$(curl -s -X POST 'https://'${OT_CONTROLLER_URL}'/v1/rooms' \
            -H "Authorization: Bearer ${OT_TOKEN}" -H 'Content-Type: application/json' \
            -d '{"password": null, "enable_sip": false, "waiting_room": false}' )

    if [ "$(echo "$E_ROOM_ID" | grep \"id\":)" = "" ]; then
        echo "- something went wrong:"
        echo "$E_ROOM_ID"
        exit 1
    fi

    E_ROOM_ID="$(echo "$E_ROOM_ID" | jq -r .id)"
    ot_get_invite
    echo "Room: ${OT_PROTO}${OT_MAIN_URL}/room/$E_ROOM_ID Guest: $INVITE_LINK"
}

ot_get_invite () {
    EXPIRATION_DATE=$(date --date="-${DEFAULT_EXPIRATION_HOURS} hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    INVITE_CODE=$(curl -s -X POST "https://${OT_CONTROLLER_URL}/v1/rooms/${E_ROOM_ID}/invites" \
            -H "Authorization: Bearer ${OT_TOKEN}" -H 'Content-Type: application/json' \
            -d '{"expiration": "'${EXPIRATION_DATE}'"}' | jq -r '.invite_code' \
            )
    INVITE_LINK="${OT_PROTO}${OT_MAIN_URL}/invite/${INVITE_CODE}"
}

ot_get_rooms () {
    ROOM_LIST=$(curl -s "https://${OT_CONTROLLER_URL}/v1/rooms?per_page=${GET_MAX_EVENTS}" \
    -H 'Content-Type: application/json' \
    -H "authorization: Bearer $OT_TOKEN")

    ROOM_COUNT="$(echo "$ROOM_LIST" | jq '. | length')"
    ROOM_COUNT=$((ROOM_COUNT - 1))

    echo $ROOM_LIST > /tmp/rl

    echo "number,room id"

    for ROOM in $(seq 0 $ROOM_COUNT); do
        E_ROOM_ID=$(echo $ROOM_LIST | jq -r '.['$ROOM'] | .id')
        echo "$ROOM $E_ROOM_ID"
    done
}

ot_get_room_info () {
    ROOM_ID=$1
    if [ "$ROOM_ID" = "" ]; then
        echo "please use the room id as parameter"
        usage | grep -- --info
    fi
    ROOM_INFO=$(curl -s "https://${OT_CONTROLLER_URL}/v1/rooms/$ROOM_ID" \
    -H 'Content-Type: application/json' \
    -H "authorization: Bearer $OT_TOKEN")

    echo $ROOM_INFO
}

ot_get_events () {
  EVENT_LIST=$(curl -s "https://${OT_CONTROLLER_URL}/v1/events?per_page=${GET_MAX_EVENTS}&adhoc=false" \
    -H 'Content-Type: application/json' \
    -H "authorization: Bearer $OT_TOKEN")

    EVENT_COUNT="$(echo "$EVENT_LIST" | jq '. | length')"
    EVENT_COUNT=$((EVENT_COUNT - 1))

    echo "$EVENT_LIST" > /tmp/el

    echo "number,title,room_link,start,end,sip,password,guest_link"

    for EVENT in $(seq 0 $EVENT_COUNT); do
        E_ROOM_ID=$(echo $EVENT_LIST | jq -r '.['$EVENT'] | .room.id')
        E_ROOM_LINK="${OT_PROTO}${OT_MAIN_URL}/room/$E_ROOM_ID"
        E_ROOM_TITLE=$(echo $EVENT_LIST | jq '.['$EVENT'] | .title')
        E_START=$(echo $EVENT_LIST | jq '.['$EVENT'] | .starts_at.datetime')
        E_END=$(echo $EVENT_LIST | jq '.['$EVENT'] | .ends_at.datetime')
        E_SIP=$(echo $EVENT_LIST | jq '.['$EVENT'] | "\(.room.sip_tel),,\(.room.sip_id),,\(.room.sip_password)"')
        E_PASSWORD=$(echo $EVENT_LIST | jq '.['$EVENT'] | .room.password')
        ot_get_invite
        echo "$EVENT $E_ROOM_TITLE,$E_ROOM_LINK,$E_START,$E_END,$E_SIP,$E_PASSWORD,$INVITE_LINK"
    done
}

case "$1" in
    -l|--list-events)
            ot_login
            ot_get_events ;;
    -c|--create-room)
            ot_login
            ot_create_room ;;
    -r|--rooms )
            ot_login
            ot_get_rooms ;;
    -i|--info )
            ot_login
            ot_get_room_info $2 ;;
    *) usage ;;
esac