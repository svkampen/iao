#importonce

#import "zeropage.inc"
#import "pseudo.lib"
#import "engine/scrn_addr.inc"
#import "engine/val_to_dec_str.asm"

update_money:
        // add subsidy to balance
        clc
        lda money
        adc subsidy
        sta money

        lda money + 1
        adc subsidy + 1

        bcc !save_high+

        // In this case, we've overflowed. Just cap the money to $ffff
        lda #$ff
        sta money

!save_high:
        sta money + 1

        // subtract expenditure from balance
        lda money
        clc
        sbc expenditure
        lda money + 1
        sbc expenditure + 1
        bcc !end+

        // Negative overflow, we've spent more than we have
        lda stat_flg
        ora #%10000000
        sta stat_flg
!end:
        rts

//TODO
update_subsidy:
        rts

update_expenditure:
        ldx #35                                         // 2
        lda #0                                          // 2
        sta expenditure + 1 // set high byte to 0       // 3
        clc                                             // 2

!loop:
        adc investment_table, x                         // 4
        bcc !cont+                                      // 2/3/4
        clc                                             // 2
        inc expenditure + 1                             // 5

!cont:
        dex                                             // 2
        bne !loop-                                      // 2/3/4
        sta expenditure                                 // 3
        rts                                             // 6

        // ~670 cycles


.var vic = 2 * $4000
// pointers to game screens, must be multiple of $0400
.var screen_main      = vic + 0 * $0400
.var screen_subsidies = vic + 1 * $0400
.var screen_log       = vic + 2 * $0400
.var screen_options   = vic + 3 * $0400


write_money:
        mov16 money : c_h_lo
        jsr itoa
        // update screen 1
        mov dec_char : screen_main+coordToAddr(1, 24)
        mov dec_char : screen_main+coordToAddr(2, 24)
        mov dec_char : screen_main+coordToAddr(3, 24)
        mov dec_char : screen_main+coordToAddr(4, 24)
        mov dec_char : screen_main+coordToAddr(5, 24)
        // update screen 2
        mov dec_char : screen_subsidies+coordToAddr(1, 24)
        mov dec_char : screen_subsidies+coordToAddr(2, 24)
        mov dec_char : screen_subsidies+coordToAddr(3, 24)
        mov dec_char : screen_subsidies+coordToAddr(4, 24)
        mov dec_char : screen_subsidies+coordToAddr(5, 24)
        // update screen 3
        mov dec_char : screen_log+coordToAddr(1, 24)
        mov dec_char : screen_log+coordToAddr(2, 24)
        mov dec_char : screen_log+coordToAddr(3, 24)
        mov dec_char : screen_log+coordToAddr(4, 24)
        mov dec_char : screen_log+coordToAddr(5, 24)
        rts

write_subsidy:

        rts

write_expenditure:
        rts
