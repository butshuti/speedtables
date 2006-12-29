#
# Ctable Server 
#
# $Id$
#

package require Tclx
package require ctable_net

namespace eval ::ctable_server {
  variable registeredCtables
  variable evalEnabled 1

#
# Variables for "shutdown" command
#
  variable shuttingDown 0
  variable clientList {}

#
# register - register a table for remote access
#
proc register {ctableUrl localTableName {type ""}} {
    variable registeredCtables

    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir exportedTableName options

    serverlog "register $ctableUrl $exportedTableName $type"
    set registeredCtables($exportedTableName) $localTableName

    start_server $port
}

#
# register_instantiator - register a ctable creator
#
proc register_instantiator {cTable} {
    variable registeredCtableCreators

    set registeredCtableCreators($cTable) ""
}

proc register_redirect {ctableUrl redirectedToCtableUrl} {
    variable registeredCtableRedirects

    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir table options
    start_server $port

    serverlog "register redirect table $table to $redirectedToCtableUrl"
    set registeredCtableRedirects($table:$port) $redirectedToCtableUrl
}

#
# start_server - setup  server socket
#
proc start_server {{port 11111}} {
    variable portSockets

    if {[info exists portSockets($port)]} {
	return
    }
    set serverSock [socket -server ::ctable_server::accept_connection $port]

    set portSockets($port) $serverSock
}

#
# shutdown_servers - close server sockets and flag the system to shut down
#
proc shutdown_servers {} {
    variable portSockets
    variable shuttingDown

    foreach {port sock} [array get portSockets] {
	close $sock
	unset portSockets($port)
    }
    set shuttingDown 1
}

#
# accept_connection - accept a client connection
#
proc accept_connection {sock ip port} {
    variable clientList
    lappend clientList $sock $ip $port
    serverlog "connect from $sock $ip $port"

    set theirPort [lindex [fconfigure $sock -sockname] 2]

    fconfigure $sock -blocking 0 -translation auto
    fileevent $sock readable [list ::ctable_server::remote_receive $sock $theirPort]

    puts $sock [list ctable_server 1.0 ready]
    flush $sock
}

#
# remote_receive - receive data from the remote side
#
proc remote_receive {sock myPort} {
    global errorCode errorInfo
    variable registeredCtableRedirects
    variable ctableUrlCache

    if {[eof $sock]} {
	variable clientList
	variable shuttingDown
	set i [lsearch $clientList $sock]
	if {$i >= 0} {
	    set j [expr $i + 2]
	    set clientList [lreplace $clientList $i $j {}]
	}
	serverlog "EOF on $sock, closing"
	close $sock
	if {$shuttingDown && [llength $clientList] == 0} {
	    exit 0
	}
	return
    }

    if {[gets $sock line] >= 0} {
	lassign $line ctableUrl line 

	if {![info exists ctableUrlCache($ctableUrl)]} {
	    lassign [::ctable_net::split_ctable_url $ctableUrl] host port dir table options

	    if {[info exists registeredCtableRedirects($table:$myPort)]} {
#puts "sending redirect to $sock, $ctableUrl -> $registeredCtableRedirects($table:$myPort)"
		puts $sock [list r $registeredCtableRedirects($table:$myPort)]
		flush $sock
		return
	    }
#puts "setting ctable url cache $ctableUrl -> $table"
	    set ctableUrlCache($ctableUrl) $table
	} else {
	    set table $ctableUrlCache($ctableUrl)
	}

	if {[catch {remote_invoke $sock $table $line} result] == 1} {
	    serverlog "$table: $result" \
		"In ($sock) $ctableUrl $line"; # $::errorInfo
	    # look at errorInfo if you want to know more, don't send it
	    # back to them -- it exposes stuff about us they don't care
	    # about
	    if {$errorCode == "ctable_quit"} return
	    ### puts stdout [list e $result "" $errorCode]
	    puts $sock [list e $result "" $errorCode]
	} else {
	    ### puts stdout [list k $result]
	    puts $sock [list k $result]
	}

	flush $sock
    }
}

#
# instantiate - create an instance of a ctable and register it
#
proc instantiate {ctableCreator ctable} {
    variable registeredCtables
    variable registeredCtableCreators

    if {![info exists registeredCtableCreators($ctableCreator)]} {
	error "unregistered ctable creator: $ctableCreator" "" CTABLE
    }

    if {[info exists registeredCtables($ctable)]} {
	#error "ctable '$ctable' of creator '$ctableCreator' already exists" "" CTABLE
	return ""
    }

    register $ctable
    return [$ctableCreator create $ctable]
}

proc remote_invoke {sock ctable line} {
    variable registeredCtables
    variable registeredCtableCreators
    variable evalEnabled

    ### puts "remote_invoke '$sock' '$line'"

    set remoteArgs [lassign $line command]

    ### puts "command '$command' ctable '$ctable' args '$remoteArgs'"

    switch $command {
	"shutdown" {
	    shutdown_servers
	}

	"quit" {
	    close $sock
	    error "quit" "" ctable_quit
	}

	"create" {
	    return [instantiate $ctable [lindex $remoteArgs 0]]
	}

	"tablemakers" {
	    return [lsort [array names registeredCtableCreators]]
	}

	"tables" {
	    return [array names registeredCtables]
	}

	"eval" {
	    if {!$evalEnabled} {
		error "not permitted"
	    }

	    return [uplevel #0 [linsert $remoteArgs 0 $ctable]]
	}

	"help" {
	    return "quit; create tableCreator tableName; tablemakers; tables; or a ctable name"
	}
    }

    if {![info exists registeredCtables($ctable)]} {
	error "ctable $ctable not registered on this server" "" CTABLE
    }

    set myCtable $registeredCtables($ctable)

    switch -glob -- $command {
	search* {
	    set cmd [linsert $remoteArgs 0 $myCtable $command -write_tabsep $sock]
#puts "search command '$cmd'"
#puts "start multiline response"
	    puts $sock "m"
#puts "evaling '$cmd'"
	    set code [catch {eval $cmd} result]
	    puts $sock "\\."
	    ### puts "start sent multiline terminal response"
	    flush $sock
	    return -code $code $result
	}

	default {
	    set cmd [linsert $remoteArgs 0 $myCtable $command]
#puts "standard command '$cmd'"
	    ### puts '$cmd'
	    return [eval $cmd]
	}
    }
}

proc serverlog {args} {
    if [llength $args] {
	set message "[clock format [clock seconds]] [pid]: [join $args "\n"]"
	if {[llength $args] > 1} {
	    set message "\n$message"
	}
	puts $message
    }
}

}

package provide ctable_server 1.0

#get, set, array_get, array_get_with_nulls, exists, delete, count, foreach, sort, type, import, import_postgres_result, export, fields, fieldtype, needs_quoting, names, reset, destroy, statistics, write_tabsep, or read_tabsep
