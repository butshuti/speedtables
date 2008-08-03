# $Id$

source test_common.tcl

source index-defaults.ct

package require Indef

# set to 1 to create some spiciness
set spicy_brains 1

set t [indef create #auto]

proc test_index {table args} {
  set comp [list $args]
  set longway 0
  $table search -compare $comp -key dummy -code { incr longway }
  set shortway [$table search -compare $comp]
  if {"$shortway" != "$longway"} {
    error "$table search -compare $comp - Longway was '$longway' shortway was '$shortway'"
  }
}

$t index create color
$t index create flavor
$t index create spiciness

set foods {pizza sugar toast waffles soup nuts}
set colors {red orange yellow white maroon}
set flavors {sweet sour cheesy pepper acid}

proc re {list} {
  return [lindex $list [expr {int(rand() * [llength $list])}]]
}

for {set i 0} {$i < 100} {incr i} {
  if [expr {int(rand() * 2)}] {
    $t set $i id [re $foods]$i color [re $colors]
  } else {
    $t set $i id [re $foods]$i flavor [re $flavors]
  }
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  if [expr {int(rand() * 2)}] {
    if {$spicy_brains} {
      $t set $j spiciness [expr {int(rand() * 100) * 0.1}]
    } else {
      $t set $j id [re $foods]$i flavor [re $flavors]
    }
  } else {
    if {[$t exists $j]} {
      $t delete $j
    } else {
      $t set $j id [re $foods]$i flavor [re $flavors]
    }
  }
}

test_index $t = color red
test_index $t = flavor cheesy
test_index $t > spiciness 5

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  if {[$t exists $j]} {
    $t delete $j
  } else {
    $t set $j id [re $foods]$i flavor [re $flavors]
  }
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t delete $j
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j id [re $foods]$j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

test_index $t = color red
test_index $t = flavor cheesy
test_index $t > spiciness 5
test_index $t >= spiciness 5
test_index $t <= spiciness 5
test_index $t < spiciness 5
test_index $t match flavor che*
test_index $t notmatch flavor che*
test_index $t match_case flavor che*
test_index $t notmatch_case flavor che*
test_index $t range spiciness 1 4
test_index $t in flavor {acid cheesy}

