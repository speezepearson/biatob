package main

import (
	"io/ioutil"
	"log"
	"net/http"
)

func createPredictionHandler(w http.ResponseWriter, r *http.Request) {
	data, err := ioutil.ReadAll(r.Body)
	if err != nil {
		log.Println("createPredictionHandler:", err)
		return
	}

	log.Println("lol creating prediction? ", data)
}

func main() {
	staticFiles := http.FileServer(http.Dir("./elm/dist"))
	http.Handle("/static", staticFiles)
	http.HandleFunc("/api/CreatePrediction", createPredictionHandler)

	log.Println("got a server yo: http://localhost:8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal(err)
	}
}
