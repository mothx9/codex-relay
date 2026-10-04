// Package web embeds the PWA; production requires no JavaScript server runtime.
package web

import (
	"embed"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed *.html *.css *.js *.webmanifest *.svg *.png
var assets embed.FS

func Handler() http.Handler {
	f := http.FileServer(http.FS(assets))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || strings.HasPrefix(r.URL.Path, "/session/") {
			b, _ := fs.ReadFile(assets, "index.html")
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write(b)
			return
		}
		f.ServeHTTP(w, r)
	})
}
