package main

import (
	"io/ioutil"
	"log"
	"net/http"
)

func createMarketHandler(w http.ResponseWriter, r *http.Request) {
	data, err := ioutil.ReadAll(r.Body)
	if err != nil {
		log.Println("createMarketHandler:", err)
		return
	}

	log.Println("lol creating market? ", data)
}

func main() {
	staticFiles := http.FileServer(http.Dir("./elm/dist"))
	http.Handle("/static", staticFiles)
	http.HandleFunc("/api/CreateMarket", createMarketHandler)

	log.Println("got a server yo: http://localhost:8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal(err)
	}
}
