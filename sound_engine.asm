;==============================================================================
; sound_engine.asm -- blocking piezo square-wave player
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; The Tandy 200 has no sound chip.  We toggle 8155 Port B bit 5 in a
; CPU delay loop.  Bit 0 stays 1 so LCD chip-select is never dropped.
; Bit 4 stays 0 so we cannot power the machine off.  VirtualT has no
; PA/PB latch: never IN these ports.
;
; PLAY_INTRO walks INTRO_NOTES (delay C, half-cycles B).  C=0, B<>0 is
; a rest.  C=0, B=0 ends.  The whole jingle is blocking: the game loop
; does not run until the last note finishes.
;
; DEATH_SOUND is not a melody.  It lengthens the half-period delay each
; step so the pitch falls for ~1.3s, then a short rest and a low pop.
;==============================================================================

PLAY_INTRO:
        PUSH    B
        PUSH    D
        PUSH    H
        LXI     H,INTRO_NOTES
PI1:    MOV     A,M                     ; C = delay / 0 = rest or end
        INX     H
        MOV     C,A
        MOV     A,M                     ; B = half-cycles or rest count
        INX     H
        MOV     B,A
        ORA     C
        JZ      PI_DONE
        MOV     A,C
        ORA     A
        JZ      PI_REST
        CALL    SND_TONE
        JMP     PI1
PI_REST:
        CALL    SND_REST
        JMP     PI1
PI_DONE:
        MVI     A,PB_IDLE
        OUT     PIO_PB
        POP     H
        POP     D
        POP     B
        RET

; Downward wail then a low thunk.  Blocking.  Pac is still on screen.
DEATH_C0        EQU     28              ; start ~2.7 kHz
DEATH_C1        EQU     249             ; stop  when C reaches this
DEATH_HLF       EQU     8               ; half-cycles at each delay
DEATH_GAP       EQU     28              ; rest after the sweep (~40 ms)
DEATH_POPN      EQU     4               ; half-cycles in the pop

DEATH_SOUND:
        PUSH    B
        MVI     C,DEATH_C0
DSW1:   MVI     B,DEATH_HLF
        CALL    SND_TONE
        INR     C
        MOV     A,C
        CPI     DEATH_C1
        JC      DSW1
        MVI     B,DEATH_GAP
        CALL    SND_REST
        MVI     B,DEATH_POPN
DSP1:   MVI     A,PB_BEEP
        OUT     PIO_PB
        CALL    SND_POPDLY
        MVI     A,PB_IDLE
        OUT     PIO_PB
        CALL    SND_POPDLY
        DCR     B
        JNZ     DSP1
        POP     B
        RET

; ~5.8 ms (4 * 256 inner counts).  Half-period ~86 Hz for the pop.
SND_POPDLY:
        PUSH    B
        MVI     C,4
SPD1:   MVI     B,0
SPD2:   DCR     B
        JNZ     SPD2
        DCR     C
        JNZ     SPD1
        POP     B
        RET

; B = number of half-cycles, C = inner delay per half.  Ends speaker off.
SND_TONE:
        PUSH    B
ST1:    MVI     A,PB_BEEP
        OUT     PIO_PB
        CALL    SND_DLY
        MVI     A,PB_IDLE
        OUT     PIO_PB
        CALL    SND_DLY
        DCR     B
        JNZ     ST1
        POP     B
        RET

; Inner wait.  Cycles = 33 + 14*C  (see sound_data.asm header).
SND_DLY:
        PUSH    B
        MOV     B,C
SD1:    DCR     B
        JNZ     SD1
        POP     B
        RET

; Rest: B times an inner 256-count loop, speaker idle.  ~2 ms each.
SND_REST:
        PUSH    B
        MVI     A,PB_IDLE
        OUT     PIO_PB
SR1:    MVI     C,0
SR2:    DCR     C
        JNZ     SR2
        DCR     B
        JNZ     SR1
        POP     B
        RET
