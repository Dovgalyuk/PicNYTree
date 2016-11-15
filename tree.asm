              LIST        P=16F628
              INCLUDE     "p16f628.inc"
;
; PORTA
;   7 6 | 5 4 | 3 2 1 0
;       |     | mode
;       |     +--------
;       | speed
;       +--------------
;  brightness
;
;

; текущее значение выводов светодиодной матрицы
TEMP		equ	0x70
; текущий режим
MODE		equ	0x71
; 0й бит = будет ли следующий цикл включением (1) или выключением (0)
;ONOFF		equ	0x72
; время в течение которого светодиоды будут гореть
T_ON		equ	0x73
; время в течение которого светодиоды будут погашены
T_OFF		equ	0x74
; скорость переключения между фазами
SPEED		equ	0x75
; временная переменная для процедуры xor2loop
XORTEMP		equ	0x76
; текущий режим процедуры, меняющей режимы
CURMODE		equ	0x77
; время до переключения режимов
CURMODECOUNT	equ	0x78
; сохраненное значение регистра W
W_TEMP		equ	0x79
; сохраненное значение регистра STATUS
STATUS_TEMP	equ	0x7A
; яркость
BRIGHTNESS	equ	0x7B
; задержка между сменой состояний
DELAY		equ	0x7C

; последний динамический режим
LASTMODE	equ	9

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RESET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		org	0x000
		goto	Start
		org	0x004
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; interrupt
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		movwf	W_TEMP		; save registers
		swapf	STATUS, W
		movwf	STATUS_TEMP

		bcf	INTCON, T0IF	; clear interrupt flag

		movfw	PORTA		; get mode
		andlw	0x0F
		subwf	MODE, W
		btfss	STATUS, Z		; don't init if not changed
		call	Init

		movfw	MODE		; get next state
		call	LoopTable

		movlw	0x08
		movwf	DELAY

		rrf	PORTA, W	; Get speed
		movwf	SPEED
		rrf	SPEED, F
		rrf	SPEED, F
		rrf	SPEED, F
		movlw	0x03
		andwf	SPEED, F
		movf	SPEED, F
CalcTMR
		btfsc	STATUS, Z
		goto	EndCalcTMR
		bcf	STATUS, C
		rlf	DELAY, F
		decf	SPEED, F
		goto	CalcTMR
EndCalcTMR
		movfw	DELAY
		sublw	0xff
		movwf	TMR0		; set timer

		swapf	STATUS_TEMP, W	; restore registers
		movwf	STATUS
		swapf	W_TEMP, F
		swapf	W_TEMP, W

		retfie			; return and enable interrupts




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; START
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Start         
		movlw	0x07
		movwf	CMCON		;Disable comparators

		clrwdt
		bsf	STATUS, RP0
; bank1
		movlw	b'11000111'	; bits0..3 - divisor
		movwf	OPTION_REG & 0x7f
		movlw	b'11111111'         ;Define I/O on Port A to input
		movwf	TRISA & 0x07F
		movlw	b'00000000'         ;Define I/O on Port B to output
		movwf	TRISB & 0x07F
		movlw	b'00000000'
		movwf	PCON & 0x07F		; clock = 32 kHz
; bank0
		bcf	STATUS, RP0

		movlw	0x0f
		movwf	XORTEMP		; init XORTEMP

		movlw	b'11100000'
		movwf	INTCON
		movlw	0xff
		movwf	MODE		; init mode
		movwf	TMR0
		movwf	TEMP

WaitInit
		incf	MODE, W		; wait until mode<>ff
		btfsc	STATUS, Z
		goto	WaitInit

MainLoop
					; calculate time
		rlf	PORTA, W	; Get 2 MSB
		movwf	BRIGHTNESS
		rlf	BRIGHTNESS, F
		rlf	BRIGHTNESS, F
		rlf	BRIGHTNESS, F
		movlw	0x03*2
		andwf	BRIGHTNESS, F

		movlw	0x03
		movwf	T_ON
		movlw	0x01
		movwf	T_OFF
		movf	BRIGHTNESS, F
CalcT_OFF
		btfsc	STATUS, Z
		goto	EndCalcT_OFF
		bcf	STATUS, C
		rlf	T_OFF, F
		decf	BRIGHTNESS, F
		goto	CalcT_OFF
EndCalcT_OFF

		movfw	TEMP		; set outputs on
		movwf	PORTB

		movfw	T_ON
OnLoop
		addlw	-1
		btfsc	STATUS, Z
		goto	endOnLoop
		goto	OnLoop
endOnLoop

		movfw	T_OFF
OffLoop
		addlw	-1
		btfsc	STATUS, Z
		goto	endOffLoop
		clrf	PORTB
		goto	OffLoop
endOffLoop
		goto	MainLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Init TEMP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Init
		movfw	PORTA		; get mode
		andlw	0x0F
		movwf	MODE
		call	InitTable
		movwf	TEMP
		return

InitTable
		addwf	PCL, F
; scroll loop
		retlw	0x01			;mode 0 ok (4 red or 4 green)
		retlw	0xfe			;mode 1 ok
		retlw	0x0f			;mode 2 ok
		retlw	0x03			;mode 3 ok
		retlw	0x11			;mode 4 bad (3 red and 3 green)
		retlw	0x33			;mode 5 bad (4 red and 4 green)
; swap loop
		retlw	0x0f			;mode 6 ok
		retlw	0xa5			;mode 7 bad (flash 1/2 leds)
; xor2 loop
		retlw	0xaa			;mode 8 ok
; random loop
		retlw	0xb1			;mode 9 ok
; constant loop
		retlw	0xaa			;mode a ok
		retlw	0x55			;mode b ok
		retlw	0x33			;mode c ok
		retlw	0xf0			;mode d ok
		retlw	0x0f			;mode e ok
; random mode
		clrf	CURMODECOUNT
		movlw	LASTMODE
		movwf	CURMODE
		goto	InitTable		;mode f


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Select loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LoopTable
		addwf	PCL, F
		goto	ScrollLoop		;mode 0
		goto	ScrollLoop		;mode 1
		goto	ScrollLoop		;mode 2
		goto	ScrollLoop		;mode 3
		goto	ScrollLoop		;mode 4
		goto	ScrollLoop		;mode 5
; swap loop
		goto	SwapLoop		;mode 6
		goto	SwapLoop		;mode 7
; xor2 loop
		goto	Xor2Loop		;mode 8
; random loop
		goto	RandomLoop		;mode 9
; constant loop
		goto	ConstantLoop		;mode a
		goto	ConstantLoop		;mode b
		goto	ConstantLoop		;mode c
		goto	ConstantLoop		;mode d
		goto	ConstantLoop		;mode e
; random mode
		goto	RandomModeLoop		;mode f


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 21.10.02
;;  rotate byte through PORTB
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ScrollLoop
		bcf	STATUS, C
		btfsc	TEMP, 0
		bsf	STATUS, C
		rrf	TEMP, F

		movfw	TEMP
		movwf	PORTB
		return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 23.10.02
;;  invert byte
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
InvertLoop
		comf	TEMP, F

		movfw	TEMP
		movwf	PORTB
		return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 23.10.02
;;  swap semi-bytes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SwapLoop
		swapf	TEMP, F

		movfw	TEMP
		movwf	PORTB
		return


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 24.10.02
;;  xor by 0x0f an 0xf0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Xor2Loop
		swapf	XORTEMP, W
		xorwf	TEMP, F
		movwf	XORTEMP

		movfw	TEMP
		movwf	PORTB
		return


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 24.10.02
;;  generate random numbers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RandomLoop
		movlw	0
		btfsc	TEMP, 3
		xorlw	1
		btfsc	TEMP, 4
		xorlw	1
		btfsc	TEMP, 5
		xorlw	1
		btfsc	TEMP, 7
		xorlw	1
		sublw	0
		rlf	TEMP, F

		movfw	TEMP
		movwf	PORTB
		return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 24.10.02
;;  последовательная смена режимов
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RandomModeLoop
		movfw	CURMODE
		call	LoopTable

		incfsz	CURMODECOUNT, F
		return

		decf	CURMODE, F		; next mode
		movfw	CURMODE
		addlw	1
		btfsc	STATUS, Z
		movlw	LASTMODE+1
		addlw	-1
		movwf	CURMODE
		call	InitTable
		movwf	TEMP
		return


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 23.10.02
;;  don't changes TEMP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ConstantLoop
		movfw	TEMP
		movwf	PORTB
		return

		org	0x100
endOfProgram

		end
