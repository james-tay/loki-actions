/*
   Build

     % go get gopkg.in/yaml.v2
     % go build loki-actions.go

   Sample YAML configuration:

     lokiURL: http://loki.example.com:3100
     period: 600 # number of seconds to look into the past
     preAction: /path/to/pre-script.sh # run this before performing jobs
     postAction: /path/to/post-script.sh # run this after all jobs complete
     jobs:
       - name: detect the oh-dear condition
         query: "{job=\"syslog_messages\"} |~ \"oh dear\""
	 action: "curl http://www.2longbeans.net/oh_dear"
       - name: detect other stuff
         ...

   Description

     This program reads a YAML file which contains 1 or more loki search
     queries. Log entries up to "period" seconds ago are searched and if
     any matches are found, they are consolidated into a multi-line message
     buffer and delivered into the configured action's standard input. If
     pre/post scripts are configured, then they are run before/after the
     loki query jobs are executed.
*/

package main 

import (
  "os"
  "fmt"
  "time"
  "strings"
  "strconv"
  "io/ioutil"
  "net/url"
  "net/http"
  "os/exec"
  "encoding/json"

  "gopkg.in/yaml.v2"		// Reference - https://gopkg.in/yaml.v2
)

/*
   The following data structures must match the YAML we'll be parsing.
   Note:
     - field names MUST start with an uppercase character (why????). 
     - annotations will be used by the yaml library during parsing.
*/

type S_Job struct {
  Name string `yaml:"name"`
  Query string `yaml:"query"`
  Action string `yaml:"action"`
}

type S_Config struct {
  LokiURL string `yaml:"lokiURL"`
  Period int64 `yaml:"period"`
  PreAction string `yaml:"preAction"`
  PostAction string `yaml:"postAction"`
  Jobs []S_Job `yaml:"jobs"`
}

const G_LokiQueryUri = "loki/api/v1/query_range"
var G_Shell string
var G_Debug int

/* ------------------------------------------------------------------------- */

func f_exec (action string, events string) {
  cmd := exec.Command (G_Shell, "-c", action)
  cmd.Stdin = strings.NewReader (events)
  out, err := cmd.CombinedOutput()
  if (err != nil) {
    fmt.Printf ("WARNING: '%s' - %s\n", action, err)
  } else {
    fmt.Printf ("NOTICE: '%s' completed.\n", action)
  }
  if (len(out) > 0) && (G_Debug > 0) {
    s := string(out)
    fmt.Printf ("DEBUG: %s\n", strings.TrimSuffix(s,"\n"))
  }
}

func main () {

  /* parse commandline, read yaml file, parse yaml contents */

  if (len (os.Args) != 2) {
    fmt.Printf ("Usage: %s <config.yaml>\n", os.Args[0])
    os.Exit (1)
  }

  yFile, err := ioutil.ReadFile (os.Args[1])
  if (err != nil) {
    fmt.Printf ("FATAL! Cannot read %s - %s\n", os.Args[1], err)
    os.Exit (1)
  }

  var cfg S_Config
  err = yaml.Unmarshal (yFile, &cfg)
  if (err != nil) {
    fmt.Printf ("FATAL! Cannot parse %s - %s\n", os.Args[1], err)
    os.Exit (1)
  }

  var ok bool
  var debug string

  G_Shell, ok = os.LookupEnv("SHELL")
  if !ok {
    G_Shell = "/bin/sh"
  }
  debug, ok = os.LookupEnv("DEBUG")
  if !ok {
    G_Debug = 0
  } else {
    G_Debug, _ = strconv.Atoi(debug)
  }

  if (G_Debug > 0) {
    fmt.Printf ("DEBUG: cfg - %#v\n", cfg)
  }

  /* if a preAction was defined, execute it now */

  if (len(cfg.PreAction) > 0) {
    f_exec (cfg.PreAction, "")
  }

  /*
     iterate through all loki queries the user has configured. Note that all
     queries use a standard start time.
  */

  now := time.Now().Unix()
  start := now - cfg.Period
  for _, element := range (cfg.Jobs) {

    params := url.Values{}
    params.Add("query", element.Query)
    params.Add("start", fmt.Sprintf("%d000000000", start))

    url := fmt.Sprintf ("%s/%s?%s",
             cfg.LokiURL, G_LokiQueryUri, params.Encode())
    resp, err := http.Get (url)
    if (err != nil) {
      fmt.Printf ("FATAL! '%s' failed - %s\n", url, err)
      os.Exit (1)
    }
    if (resp.StatusCode != 200) {
      fmt.Printf ("FATAL! '%s' returned - %s.\n", url, resp.Status)
      os.Exit (1)
    } else {
      body, err := ioutil.ReadAll(resp.Body)
      if (err != nil) {
        fmt.Printf ("FATAL! Cannot read response for '%s' - %s\n", url, err)
        os.Exit (1)
      }

      /* if we've made it here, read the (json) body of the http response  */

      var events = ""
      var obj interface{}
      err = json.Unmarshal (body, &obj)
      if (err != nil) {
        fmt.Printf ("FATAL! Cannot parse JSON from '%s' - %s\n", url, err)
        os.Exit (1)
      }

      /*
         Recall that "obj" has the structure, and we want to iterate over the
         "values" array. Since "obj" is interface{}, we need to navigate down
         to the "values" field.

         {
           "data": {
             "result": [
               {
                 "stream": {
                   "filename": "/data/rsyslog/log-services2/messages",
                    "job": "syslog_messages"
                  },
                  "values": [
                    [
                      "1577647893789739408",
                      "Dec 29 14:31:33 nybox kernel: IN=eth0 ..."
                    ],
                    ...
                  ]
               }
             ],
             "resultType": "streams"
           },
           "status": "success"
         }
      */

      data := obj.(map[string]interface{})["data"].(interface{})
      result := data.(map[string]interface{})["result"].(interface{})
      result_a:= result.([]interface{})
      if (len(result_a) > 0) {
        values := result_a[0].(map[string]interface{})["values"].(interface{})
        values_a := values.([]interface{})

        /* if one or more "values" matched this query, add them to "events" */

        events = events + fmt.Sprintf ("\n[%s]\n", element.Name)
        for i:=0 ; i < len(values_a) ; i++ {
          msg := fmt.Sprintf("%s", values_a[i].([]interface{})[1])
          events = events + fmt.Sprintf ("%s\n", msg)

        } /* ... iterate over loki results */
      } /* ... if we received results */

      if (len(events) > 0) {
        fmt.Printf ("NOTICE: events found for '%s'.\n", element.Query)
        f_exec (element.Action, events)
      } else {
        fmt.Printf ("NOTICE: no results for '%s'.\n", element.Query)
      }

    } /* ... if loki query is http 200 */
  } /* ... iterate over cfg.Jobs[] */

  /* if a postAction was defined, execute it now */

  if (len(cfg.PostAction) > 0) {
    f_exec (cfg.PostAction, "")
  }

} /* ... main() */

