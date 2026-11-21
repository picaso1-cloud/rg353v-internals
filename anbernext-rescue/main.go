// rg353v rescue shell — a tiny static TCP shell for when the display is dead.
//
// Listens on :2323. First line must be the password (default "ark").
// Then you get /bin/sh on the rootfs. Started from a NextUI boot hook.
package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
)

const (
	listenAddr = ":2323"
	password   = "ark"
)

func main() {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rescue: listen %s: %v\n", listenAddr, err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "rescue: listening on %s\n", listenAddr)
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(c)
	}
}

func handle(c net.Conn) {
	defer c.Close()
	fmt.Fprintf(os.Stderr, "rescue: connection from %s\n", c.RemoteAddr())
	fmt.Fprint(c, "rg353v rescue shell\r\npassword: ")

	br := bufio.NewReader(c)
	line, err := br.ReadString('\n')
	if err != nil || strings.TrimSpace(line) != password {
		fmt.Fprint(c, "denied\r\n")
		return
	}
	fmt.Fprint(c, "ok — type commands, 'exit' to close\r\n")

	cmd := exec.Command("/bin/sh", "-i")
	cmd.Stdin = br
	cmd.Stdout = c
	cmd.Stderr = c
	cmd.Env = []string{
		"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
		"HOME=/root",
		"TERM=linux",
		"PS1=rescue# ",
	}
	_ = cmd.Run()
}
