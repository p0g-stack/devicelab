package main

import "unsafe"

func uintptrOf(b []byte) uintptr     { return uintptr(unsafe.Pointer(&b[0])) }
func uintptrOfLen(l *uint32) uintptr { return uintptr(unsafe.Pointer(l)) }
