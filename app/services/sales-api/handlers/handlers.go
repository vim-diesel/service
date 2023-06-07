// Package handlers manages the different versions of the API.
package handlers

import (
	"os"

	"github.com/vim-diesel/service/foundation/web"
	"golang.org/x/exp/slog"
)

// APIMuxConfig contains all the mandatory systems required by handlers.
type APIMuxConfig struct {
	Build    string
	Shutdown chan os.Signal
	Log      *slog.Logger
}

// APIMux constructs a http.Handler with all application routes defined.
func APIMux(cfg APIMuxConfig) *web.App {
	app := web.NewApp(cfg.Shutdown)

	return app
}
