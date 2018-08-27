package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	var pwd, _ = os.Getwd()
	var port = flag.Int("port", 8080, "The port to use")
	var webroot = flag.String("webroot", pwd, "The path to the web root folder")
	flag.Parse()

	fs := http.FileServer(http.Dir(*webroot))
	http.Handle("/", fs)

	log.Println(fmt.Sprintf("Listening on port %d...", *port))
	http.ListenAndServe(fmt.Sprintf(":%d", *port), nil)
}
