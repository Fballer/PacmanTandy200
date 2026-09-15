;==============================================================================
; sound_data.asm -- Pac-Man intro theme tables
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; CPU clock is 2.4576 MHz.  One half-period of a square wave is:
;     cycles = 68 + 14*C
; because SND_TONE does MVI+OUT+CALL (35) plus SND_DLY (33+14*C).
; Full period = 136 + 28*C, so
;     C = (2457600 / freq - 136) / 28
;
; Half-cycle count for a note of T seconds:
;     halves = 2 * freq * T
; Bars 1-3 use ~75 ms notes (16ths).  Bar 4 uses ~50 ms (the run).
; A row of 0, N is a rest (speaker idle) lasting N * ~2 ms.
; A row of 0, 0 ends the song.
;==============================================================================

; Delay C for each pitch (inner-loop count per half-period).
DLY_B4          EQU     173             ; 493.5 Hz
DLY_C5          EQU     163             ; 523.0 Hz
DLY_DS5         EQU     136             ; 623.1 Hz
DLY_E5          EQU     128             ; 660.6 Hz
DLY_F5          EQU     121             ; 697.4 Hz
DLY_FS5         EQU     114             ; 738.5 Hz
DLY_G5          EQU     107             ; 784.7 Hz
DLY_GS5         EQU     101             ; 829.2 Hz
DLY_A5          EQU     95              ; 879.0 Hz
DLY_B5          EQU     84              ; 987.8 Hz
DLY_C6          EQU     79              ; 1046.7 Hz

; Half-cycles for 75 ms (bars 1-3) and 50 ms (bar 4).
HLF75_B4        EQU     74
HLF75_C5        EQU     78
HLF75_DS5       EQU     93
HLF75_E5        EQU     99
HLF75_FS5       EQU     111
HLF75_G5        EQU     118
HLF75_B5        EQU     148
HLF75_C6        EQU     157

HLF50_DS5       EQU     62
HLF50_E5        EQU     66
HLF50_F5        EQU     70
HLF50_FS5       EQU     74
HLF50_G5        EQU     78
HLF50_GS5       EQU     83
HLF50_A5        EQU     88
HLF50_B5        EQU     148             ; last note held ~150 ms

INTRO_NOTES:
        ; Bar 1: B4, B5, F#5, D#5, B5, F#5, D#5
        DB      DLY_B4,  HLF75_B4
        DB      DLY_B5,  HLF75_B5
        DB      DLY_FS5, HLF75_FS5
        DB      DLY_DS5, HLF75_DS5
        DB      DLY_B5,  HLF75_B5
        DB      DLY_FS5, HLF75_FS5
        DB      DLY_DS5, HLF75_DS5
        DB      0, 12                   ; bar line

        ; Bar 2: C5, C6, G5, E5, C6, G5, E5
        DB      DLY_C5,  HLF75_C5
        DB      DLY_C6,  HLF75_C6
        DB      DLY_G5,  HLF75_G5
        DB      DLY_E5,  HLF75_E5
        DB      DLY_C6,  HLF75_C6
        DB      DLY_G5,  HLF75_G5
        DB      DLY_E5,  HLF75_E5
        DB      0, 12

        ; Bar 3: same as bar 1
        DB      DLY_B4,  HLF75_B4
        DB      DLY_B5,  HLF75_B5
        DB      DLY_FS5, HLF75_FS5
        DB      DLY_DS5, HLF75_DS5
        DB      DLY_B5,  HLF75_B5
        DB      DLY_FS5, HLF75_FS5
        DB      DLY_DS5, HLF75_DS5
        DB      0, 12

        ; Bar 4: D#5, E5, F5, F5, F#5, G5, G5, G#5, A5, B5
        DB      DLY_DS5, HLF50_DS5
        DB      DLY_E5,  HLF50_E5
        DB      DLY_F5,  HLF50_F5
        DB      DLY_F5,  HLF50_F5
        DB      DLY_FS5, HLF50_FS5
        DB      DLY_G5,  HLF50_G5
        DB      DLY_G5,  HLF50_G5
        DB      DLY_GS5, HLF50_GS5
        DB      DLY_A5,  HLF50_A5
        DB      DLY_B5,  HLF50_B5

        DB      0, 0                    ; end
