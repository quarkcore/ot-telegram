package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
	"github.com/zalando/go-keyring"
)

func main() {
	var (
		roomInfoFlag bool
		socketFlag   string
		unauthFlag   bool
	)

	flag.BoolVar(&roomInfoFlag, "info", false, "-info #get room info of user")
	flag.StringVar(&socketFlag, "socket", "", "-socket <room-id> #run a signal socket to notify telegram bot.")
	flag.BoolVar(&unauthFlag, "unauth", false, "logout and clear session")
	flag.Parse()

	if flag.NFlag() <= 0 {
		panic("No flags provided")
	}

	err := godotenv.Load(".env")
	if err != nil {
		log.Fatal("Error loading .env file")
	}

	fmt.Println("user", os.Getenv("OT_USER"))

	if unauthFlag {
		unauth()
		fmt.Println("Logged out")
		os.Exit(0)
	} else {
		auth()
	}

	if roomInfoFlag {
		getRooms()
		os.Exit(0)
	}

	openWebSocket(socketFlag)
}

const (
	KeyringAppName = "gutloit/ot-bot"
)

func unauth() {
	keyring.Delete(KeyringAppName, os.Getenv("OT_USER"))
	keyring.Delete(KeyringAppName, os.Getenv("OT_USER")+"_refresh")
	keyring.Delete(KeyringAppName, os.Getenv("OT_USER")+"_refresh_expires_in")
	keyring.Delete(KeyringAppName, os.Getenv("OT_USER")+"_id_token")
}

type AuthResponse struct {
	AccessToken      string `json:"access_token"`
	ExpiresIn        int    `json:"expires_in"`
	RefreshExpiresIn int    `json:"refresh_expires_in"`
	RefreshToken     string `json:"refresh_token"`
	TokenType        string `json:"token_type"`
	IdToken          string `json:"id_token"`
	NotBeforePolicy  int    `json:"not-before-policy"`
	SessionState     string `json:"session_state"`
	Scope            string `json:"scope"`
}

func auth() {
	_, err := keyring.Get(KeyringAppName, os.Getenv("OT_USER"))
	if err == nil {
		fmt.Println("Already logged in: skipping auth request")
		return
	}

	fmt.Println("Logging in...")

	cloakUrl := os.Getenv("OT_KEYCLOAK_URL")
	realmName := os.Getenv("OT_REALM_NAME")

	authApiUrl := "https://" + cloakUrl + "/auth/realms/" + realmName + "/protocol/openid-connect/token"

	formData := url.Values{}
	formData.Set("username", os.Getenv("OT_USER"))
	formData.Set("password", os.Getenv("OT_PASSWORD"))
	formData.Set("client_id", os.Getenv("OT_CLIENT_ID"))
	formData.Set("scope", "openid")
	formData.Set("grant_type", "password")

	// Create a HTTP post request
	r, err := http.NewRequest("POST", authApiUrl, strings.NewReader(formData.Encode()))
	if err != nil {
		panic(err)
	}

	r.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	r.Header.Add("Content-Length", fmt.Sprintf("%d", len(formData.Encode())))
	r.Header.Add("Connection", "keep-alive")
	r.Header.Add("Accept", "*/*")
	r.Header.Add("Accept-Encoding", "gzip, deflate, br")

	client := &http.Client{}
	res, err := client.Do(r)
	if err != nil {
		panic(err)
	}

	defer res.Body.Close()

	authResponse := &AuthResponse{}
	derr := json.NewDecoder(res.Body).Decode(authResponse)
	if derr != nil {
		panic(derr)
	}

	if res.StatusCode != http.StatusOK {
		panic(res.Status)
	}

	keyring.Set(KeyringAppName, os.Getenv("OT_USER"), authResponse.AccessToken)
	keyring.Set(KeyringAppName, os.Getenv("OT_USER")+"_refresh", authResponse.RefreshToken)
	keyring.Set(KeyringAppName, os.Getenv("OT_USER")+"_refresh_expires_in", fmt.Sprintf("%d", authResponse.RefreshExpiresIn))
	keyring.Set(KeyringAppName, os.Getenv("OT_USER")+"_id_token", authResponse.IdToken)

	fmt.Println("Login successful!")
}

type Room struct {
	Id        string `json:"id"`
	CreatedBy struct {
		Id          string `json:"id"`
		Email       string `json:"email"`
		Title       string `json:"title"`
		Firstname   string `json:"firstname"`
		Lastname    string `json:"lastname"`
		DisplayName string `json:"display_name"`
		AvatarUrl   string `json:"avatar_url"`
	} `json:"created_by"`
	CreatedAt   string `json:"created_at"`
	Password    string `json:"password"`
	WaitingRoom bool   `json:"waiting_room"`
}

func getRooms() {
	accessToken, err := keyring.Get(KeyringAppName, os.Getenv("OT_USER"))
	if err != nil {
		panic(err)
	}

	controllerUrl := os.Getenv("OT_CONTROLLER_URL")
	//maxEvents := os.Getenv("OT_MAX_EVENTS")

	apiUrl := "https://" + controllerUrl + "/v1/rooms"

	r, err := http.NewRequest("GET", apiUrl, nil)
	if err != nil {
		panic(err)
	}

	r.Header.Add("Authorization", "Bearer "+accessToken)
	r.Header.Add("Content-Type", "application/json")

	client := &http.Client{}
	res, err := client.Do(r)
	if err != nil {
		panic(err)
	}

	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		panic(res.Status)
	}

	rooms := []Room{}
	derr := json.NewDecoder(res.Body).Decode(&rooms)
	if derr != nil {
		panic(derr)
	}

	fmt.Println("")
	fmt.Println("Rooms:")

	fmt.Println("Nr.  | Room Id")
	for i := 0; i < len(rooms); i++ {
		fmt.Println(strconv.Itoa(i+1) + "#   | " + rooms[i].Id)
	}
}

func openWebSocket(roomId string) {
	// ...
	fmt.Println("Opening websocket", roomId)
}
