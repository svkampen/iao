:BasicUpstart2(start)

.var vic = $0000

.var irq_line_top = $20 - 1
.var irq_line_bottom = $e8
.var irq_line_border = $fe

.var screen = vic + $0400

.var font = vic + $2800

.var lines_border_top = $30 - irq_line_top + 1

// FIXME use proper value (now using dummy testvalue)
.var lines_middle = $60

.var lines_counter = $ff

.var screen_scroll = screen + 23 * 40

#import "pseudo.lib"
#import "loader.inc"
#import "io.inc"
#import "loader.inc"
#import "joy.inc"
#import "kernal.inc"

//.var music = LoadSid(HVSC + "/MUSICIANS/0-9/20CC/van_Santen_Edwin/Take_on_Me.sid")
.var music = LoadSid("assets/Take_on_Me.sid")
//.var music = LoadSid("assets/Popcorn_Mix.sid")
//.var music = LoadSid("assets/Cyberfunk.sid")

.const ticks = 20

.const zp_timer = $d0
.const zp_event = $d1
.const zp_index = $d2

.const event_max = 4

start:
	lda #3
	sta $dd00
	lda #0
	sta sprmask
	jsr music.init

	jsr init

	sta $d020
	sta $d021

	jsr copy_image
	jsr blit_hide

	sei
	lda #$35		// Disable KERNAL and BASIC ROM
	sta $01			// Enable all RAM

	lda #<irq_top		// Setup IRQ vector
	sta $fffe
	lda #>irq_top
	sta $ffff

	lda #<dummy
	sta $fffa
	sta $fffc
	lda #>dummy
	sta $fffb
	sta $fffd

	lda #%00011011		// Load screen control:
				// Vertical scroll    : 3
				// Screen height      : 25 rows
				// Screen             : ON
				// Mode               : TEXT
				// Extended background: OFF
	sta $d011       	// Set screen control

	lda #irq_line_top
	sta $d012

	lda #$01		// Enable mask
	sta $d01a		// IRQ interrupt ON

	lda #%01111111		// Load interrupt control CIA 1:
				// Timer A underflow : OFF
				// Timer B underflow : OFF
				// TOD               : OFF
				// Serial shift reg. : OFF
				// Pos. edge FLAG pin: OFF
	sta $dc0d		// Set interrupt control CIA 1
	sta $dd0d		// Set interrupt control CIA 2

	lda $dc0d		// Clear pending interrupts CIA 1
	lda $dd0d		// Clear pending interrupts CIA 2

	lda #$00
	sta $dc0e

	lda #$01
	sta $d019		// Acknowledge pending interrupts

	cli			// Start firing interrupts

handle_input:
	// save CIA1 state
	lda $dc02
	sta key_ddr0
	lda $dc03
	sta key_ddr1
	jsr Keyboard
	bcs !+
	stx key_x
	sty key_y
	cmp #$ff
	beq !no_alpha+
	// TODO handle alphanumeric key
	cmp #$20
	beq goto_menu
!no_alpha:
	ldy key_y
	cpy #%10000000
	beq goto_menu
!:
	// restore CIA1 state
	lda #0
	sta $dc02
	lda key_ddr1
	sta $dc03
	// read joy2 state
	lda $dc00
	and #%11111
	// handle joystick
	cmp #joy_fire
	beq goto_menu
	jmp handle_input

goto_menu:
	// kill irq
	sei

	lda #$1b
	sta $d011
	lda #$c8
	sta $d016

	lda #<dummy
	sta $fffa
	sta $fffc
	sta $fffe
	lda #>dummy
	sta $fffb
	sta $fffd
	sta $ffff

	lda #$01
	sta $d01a
	// init timers
	lda #$7f
	sta $dc0d
	sta $dd0d
	lda $dc0d
	lda $dd0d

	cli

	// kill sid
	lda #0
	ldx #0
!:
	sta sid, x
	inx
	cpx #$20
	bne !-

	lda has_top_loader
	bne !+
	sei
	lda #$37
	sta $1
	cli
	jmp reset
!:
	// TODO
	lda #0
	sta prg_index
	jmp top_loader_start

init:
	// clear zero page area [2, $e0]
	ldx #2
	lda #0
!:
	sta 0, x
	inx
	cpx #$e0
	bne !-
	// setup event timer
	lda #ticks
	sta zp_timer
	ldx zp_index
	lda tbl_event, x
	sta zp_event
	// check if top loader is present
	ldx #0
	lda top_loader_start
	cmp #<top_magic
	bne !+
	lda top_loader_start + 1
	cmp #>top_magic
	bne !+
	ldx #1
!:
	stx has_top_loader
	jmp disable_events

.align $100
irq_top:
	irq

	lda #<irq_top_wedge	// Daisy chain double IRQ for stable raster
	sta $fffe
	lda #>irq_top_wedge
	sta $ffff

	inc $d012		// Trigger wedge IRQ on next line.

	lda #$01		// Acknowledge IRQ
	sta $d019

	tsx
	cli
	.for (var i=0; i<8; i++) {
		nop
	}

irq_top_wedge:
	txs

	ldx #$08
	dex
	bne *-1
	bit $ea

	lda $d012
	cmp $d012
	beq *+2
	// vv stable raster here

	ldx #0
!:
	lda coltbl, x
	sta $d020

	// TODO figure out if badline
	ldy #8
	dey
	bne *-1
	bit $ea

	inx
	lda coltbl, x
	cpx #lines_border_top
	bne !-

!bad:
	// NOTE: one cycle spilled already from previous branch

	// bad line handling
	sta $d020     // 4, 5
	sta $d021     // 4, 9
	inx           // 2, 11
	// 10 cycles left, just prepare counter for normal lines
	lda #7        // 2, 15
	sta lines_counter // 3, 18

	// TODO figure out why we need 3 cycles
	jmp !fst+

	// this is duplicated from previous loop, but hey, it works...
!:
	nop
	nop
	bit $ea

!fst:

	lda coltbl, x
	sta $d020
	sta $d021

	ldy #5
	dey
	bne *-1

	inx
	lda coltbl, x
	cpx #lines_middle
	beq !ack+

	dec lines_counter
	bne !-

	nop
	nop
	nop
	nop
	jmp !bad-

!ack:
	asl $d019

	jsr roll
	jsr roll2
	jsr sinusroll

	qri #irq_line_bottom : #irq_bottom

bad_line:
	inx
// bad line handling: only 20 out of 63 cycles
	lda coltbl, x // 4, 4
	sta $d020     // 4, 8
	inx           // 2, 10
	cpx #16       // 2, 12
	beq !ack-     // 2, 14
	bit $ea       // 3, 17
	jmp !-        // 3, 20

dummy:
	rti

irq_bottom:
	irq
	//inc $d020

	lda #$c0
	ora scroll_xpos
	sta $d016
	lda #$1a
	sta $d018

	//dec $d020
	qri2 #irq_line_border : #irq_border

irq_border:
	irq
	//inc $d020

	jsr music.play

	jsr timer

	//lda scroll
	//sta screen + 40

	jsr scroll

	lda #$14
	sta $d018
	lda #$c8
	sta $d016

	//dec $d020
	qri2 #irq_line_top : #irq_top

scroll:
	// lda abs: AD
	// rts: 60
	lda scroll_xpos
	sec
	sbc scroll_speed
	and #$07
	sta scroll_xpos
	//sta screen
	bcc !moveChars+
	rts
!moveChars:
	// Move the chars
	ldx #0
!loop:

	lda screen_scroll +1,x
	sta screen_scroll ,x
	lda screen_scroll +1+40,x
	sta screen_scroll +40,x
	inx
	cpx #40
	bne !loop-

	// print the new chars
!txtPtr:
	lda scroll_text
	cmp #$ff
	bne !noWrap+
	lda #<scroll_text
	sta !txtPtr-+1
	lda #>scroll_text
	sta !txtPtr-+2
	jmp !txtPtr-
!noWrap:
	ora scroll_charNo
	sta screen_scroll+39
	clc
	adc #$40
	sta screen_scroll+39+40

	// Advance textpointer
	lda scroll_charNo
	eor #$80
	sta scroll_charNo
	bne !over+
!incr:
	inc !txtPtr-+1
	bne !over+
	inc !txtPtr-+2
!over:

	rts

scroll_xpos: .byte 0
scroll_speed: .byte $02
scroll_charNo: .byte 0

.align $80

coltbl:
flag:
	.byte 2, 2, 2, 2, 2, 2, 2, 2
	.byte 1, 1, 1, 1, 1, 1, 1, 1, 6, 6, 6, 6, 6, 6, 6, 6
	.byte 0, 0, 0, 0
	.byte 0, 0, 0, 0
	.byte 0, 0, 0, 0

	//.byte 1, 13, 5, 6, 11, 14, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0
rolcol:
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0
sinusrol:
	.byte 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
sinusrol_end:
	//.byte 5, 0, 5, 3, 0, 5, 3, 13, 0, 5, 3, 13, 7, 0, 5, 3
	//.byte 13, 7, 1

	.byte 1, 7, 13
	.byte 3, 5, 0, 7, 13, 3, 5, 0, 13, 3, 5, 0, 3, 5, 0, 5

	.byte 0, 0, 0, 0, 0

sinus:
	.fill $40, round($10*sin(toRadians(i*360/$80)))

roltbl:
	.byte 6, 4, 10, 7, 10, 8, 2, 9

rolpos:
	.byte 0

roll:
	// ldx abs: AE
	// rts: 60
	ldx roldelay
	dex
	stx roldelay
	bne !done+
	ldx #2
	stx roldelay

	lda rolcol + 9 - 8
	sta rolcol + 9 - 9
	sta rolcol + 9 + 9
	lda rolcol + 9 - 7
	sta rolcol + 9 - 8
	sta rolcol + 9 + 8
	lda rolcol + 9 - 6
	sta rolcol + 9 - 7
	sta rolcol + 9 + 7
	lda rolcol + 9 - 5
	sta rolcol + 9 - 6
	sta rolcol + 9 + 6
	lda rolcol + 9 - 4
	sta rolcol + 9 - 5
	sta rolcol + 9 + 5
	lda rolcol + 9 - 3
	sta rolcol + 9 - 4
	sta rolcol + 9 + 4
	lda rolcol + 9 - 2
	sta rolcol + 9 - 3
	sta rolcol + 9 + 3
	lda rolcol + 9 - 1
	sta rolcol + 9 - 2
	sta rolcol + 9 + 2
	lda rolcol + 9 - 0
	sta rolcol + 9 - 1
	sta rolcol + 9 + 1

	ldx rolpos
	inx
	txa
	and #$07
	tax
	stx rolpos

	lda roltbl, x
	sta rolcol + 9

!done:
	rts

roldelay:
	.byte 2

roll2:
	ldx flag + 23
	lda flag + 22
	sta flag + 23
	lda flag + 21
	sta flag + 22
	lda flag + 20
	sta flag + 21
	lda flag + 19
	sta flag + 20
	lda flag + 18
	sta flag + 19
	lda flag + 17
	sta flag + 18
	lda flag + 16
	sta flag + 17
	lda flag + 15
	sta flag + 16
	lda flag + 14
	sta flag + 15
	lda flag + 13
	sta flag + 14
	lda flag + 12
	sta flag + 13
	lda flag + 11
	sta flag + 12
	lda flag + 10
	sta flag + 11
	lda flag + 9
	sta flag + 10
	lda flag + 8
	sta flag + 9
	lda flag + 7
	sta flag + 8
	lda flag + 6
	sta flag + 7
	lda flag + 5
	sta flag + 6
	lda flag + 4
	sta flag + 5
	lda flag + 3
	sta flag + 4
	lda flag + 2
	sta flag + 3
	lda flag + 1
	sta flag + 2
	lda flag + 0
	sta flag + 1
	stx flag
	rts

sinusroll:
	// veeg oude plek uit
	lda #0
	ldx sinuspos
	ldy sinus, x
	sta sinusrol, y
	inx
	txa
	and #$3f
	bne !+
	pha
	jsr blit_next
	pla
!:
	tax
	stx sinuspos
	lda #1
	ldy sinus, x
	sta sinusrol, y
	// vul de rest met dezelfde kleur
!:
	sta sinusrol, y
	iny
	cpy #sinusrol_end - sinusrol
	bne !-
	rts

sinuspos:
	.byte 0

copy_image:
	ldx #0
!l:
	lda image  + $000, x
	sta screen + $000, x
	lda image  + $100, x
	sta screen + $100, x
	lda image  + $200, x
	sta screen + $200, x
	lda image  + $2e8, x
	sta screen + $2e8, x

	lda #2
	lda colors + $000, x
	sta colram + $000, x
	lda colors + $100, x
	sta colram + $100, x
	lda colors + $200, x
	sta colram + $200, x
	lda colors + $2e8, x
	sta colram + $2e8, x
	dex
	bne !l-
	rts

blit_hide:
	ldx #0
	ldy #1
!:
blit_tput:
	lda texts, x
	sta screen + 5 * 40 + (40 - $18) / 2, x
	tya
blit_cput:
	sta colram + 5 * 40 + (40 - $18) / 2, x
	inx
	cpx #$18
	bne !-
	rts

// you may not globber y!!
blit_next:
	inc screen + 5 * 40 + (40 - $18) / 2
	lda blit_tput + 1
	clc
	adc #$18
	sta blit_tput + 1
	bcc !+
	inc blit_tput + 2
!:
	// reset if at end
	ldx #<texts_end
	lda #>texts_end
	cpx blit_tput + 1
	bne !+
	cmp blit_tput + 2
	bne !+
	// TODO reset
	lda #<texts
	sta blit_tput + 1
	lda #>texts
	sta blit_tput + 2
!:
	jmp blit_hide

/*
kleurentabel:
0  0: zwart
1  1: wit
2  2: rood
3  3: cyaan
4  4: paars
5  5: groen
6  6: blauw
7  7: geel
8  8: oranje
9  9: bruin
a 10: beige
b 11: donkergrijs
c 12: grijs
d 13: licht groen
e 14: lichtblauw
f 15: lichtgrijs
*/

#import "kbd.asm"

// music begin
	*=music.location "Music"
	.fill music.size, music.getData(i)

//----------------------------------------------------------
	// Print the music info while assembling
	.print ""
	.print "SID Data"
	.print "--------"
	.print "location=$"+toHexString(music.location)
	.print "init=$"+toHexString(music.init)
	.print "play=$"+toHexString(music.play)
	.print "songs="+music.songs
	.print "startSong="+music.startSong
	.print "size=$"+toHexString(music.size)
	.print "name="+music.name
	.print "author="+music.author
	.print "copyright="+music.copyright

	.print ""
	.print "Additional tech data"
	.print "--------------------"
	.print "header="+music.header
	.print "header version="+music.version
	.print "flags="+toBinaryString(music.flags)
	.print "speed="+toBinaryString(music.speed)
	.print "startpage="+music.startpage
	.print "pagelength="+music.pagelength
// music end

.pc = * "Logo PETSCII"

.align $100
image:
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $15, $20, $08, $05, $05, $06, $14, $20, $07, $05, $17, $0F, $0E, $0E, $05, $0E, $21, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $07, $05, $06, $05, $0C, $09, $03, $09, $14, $05, $05, $12, $04, $21, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $A0, $A0, $DF, $20, $20, $A0, $A0, $A0, $DF, $20, $20, $A0, $A0, $A0, $A0, $20, $A0, $A0, $A0, $A0, $DF, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $5F, $DF, $20, $A0, $20, $20, $5F, $DF, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $20, $20, $20, $A0, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $20, $20, $20, $A0, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $20, $20, $E9, $69, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $A0, $A0, $69, $20, $20, $20, $E1, $61, $20, $20, $A0, $A0, $A0, $A0, $69, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $20, $5F, $DF, $20, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $20, $20, $5F, $DF, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $20, $20, $E9, $69, $20, $A0, $20, $20, $20, $A0, $20, $20, $E1, $61, $20, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $A0, $A0, $A0, $69, $20, $20, $A0, $20, $20, $20, $A0, $20, $A0, $A0, $A0, $A0, $20, $A0, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20

.pc = * "Logo Colram"

.align $100
colors:
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0A
	.byte $0A, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0A, $0A, $0A, $0A, $0E, $0E, $0A, $0A, $0A, $0A, $0E, $0E, $0A, $0A, $0A, $0A, $0E, $0A, $0A, $0A, $0A, $0A, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0D, $0E, $0E, $0E, $0E, $0A, $0E, $0E, $0A, $0A, $0E, $0A, $0E, $0E, $0A, $0A, $0E, $0E, $0A, $0A, $0E, $0E, $0A, $0E, $0E, $0E, $0A, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $07, $0E, $0E, $0E, $07, $0E, $07, $0E, $0E, $0E, $07, $0E, $0E, $07, $07, $0E, $0E, $07, $0E, $0E, $0E, $07, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $07, $0E, $0E, $0E, $07, $0E, $07, $0E, $0E, $0E, $07, $0E, $0E, $07, $07, $0E, $0E, $07, $0E, $0E, $0E, $07, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0D, $0E, $0E, $0E, $0D, $0E, $0D, $0E, $0E, $0D, $0D, $0E, $0E, $0D, $0D, $0E, $0E, $0D, $0E, $0E, $0E, $0D, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0D, $0E, $0E, $0E, $0D, $0E, $0D, $0D, $0D, $0D, $0E, $0E, $0E, $0D, $0D, $0E, $0E, $0D, $0D, $0D, $0D, $0D, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $03, $0E, $0E, $0E, $03, $0E, $03, $0E, $03, $03, $0E, $0E, $0E, $03, $03, $0E, $0E, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $03, $0E, $0E, $0E, $03, $0E, $03, $0E, $0E, $03, $03, $0E, $0E, $03, $03, $0E, $0E, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E

.pc = font "Custom Font"
//.var charsetPic = LoadPicture("ugly_font.gif", List().add($000000, $ffffff))
.var charsetPic = LoadPicture("arrival_font.gif", List().add($000000, $ffffff))
.function picToCharset(byteNo, picture) {
       .var ypos = [byteNo&7] + 8*[[byteNo>>9]&1]
       .var xpos = 2*[[byteNo>>3]&$3f] + [[byteNo>>10]&1]
       .return picture.getSinglecolorByte(xpos,ypos)
}
.fill $800, picToCharset(i,charsetPic)

.pc = * "Top text"

	//     0123456789abcdef0123456789abcdef
texts:
	.text "                        "
	.text "    goed gedaan hoor!   "
	.text "er zijn maar weinig die "
	.text "   zover zijn gekomen!  "
	.text "------------------------"
	.text "          drip          "
	.text "   gemaakt aan de uva   "
	.text " code: methos, flevosap "
	.text " code: theezakje, york  "
	.text " gfx: methos, flevosap  "
	.text " gfx: pepermunt, york   "
	.text "tekst: methos, pepermunt"
	.text "     sid: evs / 20cc    "
	.text " intro, credits: methos "
	.text "design: methos, flevosap"
	.text "     linken: methos     "
	.text "   testen: drip-team    "
	.text "------------------------"
	.text " soms zit het leven mee "
	.text "soms zit het tegen, maar"
	.text "  het belangrijkste is  "
	.text "    dat je weet waar    "
	.text " je naartoe wilt werken "
	.text "                        "
	.text "de tocht is belangrijker"
	.text " dan het doel bereiken! "
	.text "------------------------"
	// nog meer tekst, verzin iets leuks :p
	.text "  wij willen graag de   "
	.text "volgende mensen bedanken"
	.text "------------------------"
	.text "      marco brohet      "
	.text "   voor mentale steun   "
	.text "     robert van wijk    "
	.text " voor de leuke opdracht "
	.text "  fuat ozman voor zijn  "
	.text "  heerlijke kapsalons!  "
	.text "  en uiteraard ook ...  "
	.text "     onze moeders. :)   "
	// Verdere groetjes?
	.text "------------------------"
	.text "bedankt voor het spelen "
	.text "                        "
	.text " tot de volgende keer!  "
	.text "                        "
	.text " tekst gaat weer rond   "
	.text "------------------------"
	.text "                        "
texts_end:

scroll_text:
	.text "goed gedaan! u heeft de wereld behoed van rampen en de verenigde naties zijn erg tevreden met uw werk! "
	.text "bedankt voor het spelen van ons spel drip! "
	.text "dit is gemaakt voor de universiteit van amsterdam "
	.text "in ongeveer 5 weken... "
	.text "we hebben heel veel geleerd van dit project, "
	.text "bijvoorbeeld dat we niet te ambitieus moeten zijn! "
	.text "op de laatste dag dat we het moesten afronden, "
	.text "kwamen we erachter dat het toetsenbord en de joystick na de intro niet meer werkten! "
	.text "we hebben toen met veel stress een nieuwe driver geschreven! "
	.text "zoals ze wel vaker zeggen... "
	.text "hoe dichterbij de deadline komt, hoe creatiever en productiever je wordt! "
	.text "oja, de code staat op folkerts github. "
	.text "spreek folkert na afloop maar aan als u meer wilt weten! "
	.text "we hopen dat u net zoveel plezier "
	.text "heeft gehad als wij met het maken ervan! "
	.text "groetjes aan de c64 demoscene "
	.text "en onze vrienden op de uni "
	.text "en dank aan marco en robert voor "
	.text "het geven van uitstel voor het spel "
	.text "zo hebben we het spel "
	.text "goed kunnen testen en afronden! "
	.text "druk op spatie om terug "
	.text "te gaan naar het hoofdmenu... .. .. . . .              "
	.byte $ff

timer:
	//inc $d020
	dec zp_timer
	bne !l+
	lda #ticks
	sta zp_timer
	// advance timer
	//lda zp_event
	//sta screen + 1
	dec zp_event
	bne !l+
	// handle event
	inc zp_index
	jsr time_event
	ldx zp_index
	cpx #event_max
	bne !no_reset+
	// XXX disable events after loop?
	ldx #0
!no_reset:
	stx zp_index
	lda tbl_event, x
	sta zp_event
!l:
	//dec $d020
	rts

disable_events:
	lda #$60
	sta scroll
	sta roll
	sta roll2
	sta sinusroll
	rts

time_event:
	ldx zp_index
	cpx #1
	bne !l+
	lda #$ae
	sta roll2
	jmp !done+
!l:
	cpx #2
	bne !l+
	lda #$ae
	sta roll
	jmp !done+
!l:
	cpx #3
	bne !l+
	lda #$a9
	sta sinusroll
	jmp !done+
!l:
	cpx #4
	bne !done+
	lda #$ad
	sta scroll
!done:
	rts

tbl_event:
	.byte 16, 16, 8, 8, 16
	// TODO start bottom scroller
	// TODO add more events
