# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

# Constants
.set SECTOR_SIZE, 512
.set BYTES_PER_LINE, 16
.set LINES_PER_PAUSE, 16
.set OFFSET_DISPLAY, 7
.set SECTORS_PER_TRACK, 18
.set HEADS, 2
.set BYTES_PER_LINE, 16
.set LINES_PER_PAUSE, 16

.code16                         # Assemble for 16-bit mode
.globl start

start:
    jmp     real_start


real_start:
    movb    %dl, (boot_device) # Boot device number is passed in DL from BIOS. Save it here since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline

    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive


# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code. 

cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret

# Output the 16-bit value in BX to the screen as a 4 digit hex value	
#
# Input:  BX = Value to output	

HexChars:	.ascii "0123456789ABCDEF"

cons_write_hex:
	movw	$4, %cx
    movb    $0x0E, %ah
	
hexloop:
    rol     $4, %bx # Rotate left by 4 bits
    movw    %bx, %si # Move the value in BX into SI
    and     $0x000F, %si # Mask the lower 4 bits
    movb    HexChars(%si), %al # Move the value in HexChars into AL
	int		$0x10 # Call BIOS to display character
	loop	hexloop # Repeat the loop
	ret


# Output the value in BX as an unsigned integer
#
# Input: BX = Value to output
	
cons_write_int:
    movw    $IntBuffer + 4, %si
    movw    %bx, %ax
	
getdigit:
	xor		%dx, %dx
	movw	$10, %cx
	div		%cx
	addb	$48, %dl
	movb	%dl, (%si)
	dec		%si
	cmp		$0, %ax
	jne		getdigit
	inc		%si
	call	cons_write
	ret

harddrive:
    movw    $hd, %si
    call   cons_writeline
    call   get_starting_sector
    call   get_num_sectors         # Read sectors from disk
    call   read_sectors
    jmp    endless_loop

get_starting_sector:
    movw    $prompt_start_sector, %si
    call    cons_write
    movb    $4, max_input_amount
    call    get_input
    call    convert_input_to_int
    movw    %ax, start_sector

    ret
    
get_num_sectors:
    movw    $prompt_num_sectors, %si
    call    cons_write
    movb    $4, max_input_amount
    call    get_input
    call    convert_input_to_int
    movw    %ax, num_sectors

    ret

get_input:
    movw    $input_buffer, %si
    movb    max_input_amount, %cl 
    call    input_loop
    call    cons_write_crlf
    ret

input_loop:
    movb    $0x00, %ah          # BIOS.GetKeyboardKey
    int     $0x16               # -> AX
    
    cmp     $0x0D, %al          # Check for enter key
    je      check_input_length

    cmp     $0x08, %al          # Check for backspace key
    je      handle_backspace

    # Check if we have reached the maximum input amount
    cmp     $0, %cl             # Check if CL is zero
    je      input_loop          # Loop if CL is zero to ignore input unless it's backspace

    # Echo the character back to the user
    movb    $0x0E, %ah          # BIOS.TTYPrint
    int     $0x10               # Display the character in AL
    
    # Store the character and advance pointer
    movb    %al, (%si)
    inc     %si
    
    incb    input_length

    # Decrement our counter (in CL)
    dec     %cl
    
    jmp     input_loop          # Go back to get next character

handle_backspace:
    # Check if SI points to start of input_buffer, if so, no characters to delete
    cmp     $input_buffer, %si  
    je      input_loop

    # Move the cursor back by one space to give the impression of deletion
    movb    $0x0E, %ah          # BIOS.TTYPrint
    movb    $0x08, %al          # ASCII for backspace
    int     $0x10               # Move cursor one space back
    movb    $0x20, %al          # ASCII for space
    int     $0x10               # Print space to clear character
    movb    $0x08, %al          # ASCII for backspace
    int     $0x10               # Move cursor one space back

    # Decrease pointer
    dec     %si
    # Clear the last character from buffer
    movb    $0, (%si)
    
    # Increment our counter
    inc     %cl

    # Decrement the input_length counter if greater than 0
    cmpb    $0, input_length
    jle     input_loop
    decb    input_length
    jmp     input_loop


check_input_length:
    # Compare input_length with 0
    cmpb    $0, input_length
    jne     finish_input        # If input_length is not 0, finish input

    # Else, prompt the user to enter a value again
    call    cons_write_crlf
    movw    $prompt_no_input, %si
    call    cons_write
    movw    $input_buffer, %si
    jmp     input_loop


finish_input:
    # Calculate the effective address for null-termination
    movb    $0, (%si)

    # Clear the input_length counter
    movb    $0, input_length

    ret 

input_error:
    movw $prompt_invalid_input, %si   # Load the address of the invalid input prompt
    call cons_writeline               # Display the error message
    jmp input_loop                    # Restart input collection

convert_input_to_int:
    movw    $input_buffer, %si  # Set SI to point to the input buffer
    xor     %ax, %ax            # Clear %ax to store the final integer
    xor     %dx, %dx            # Clear %dx, used for intermediate calculations

convert_loop:
    movb    (%si), %dl          # Load the next byte from the string into %dl
    test    %dl, %dl            # Test if the byte is null (end of string)
    jz      convert_end         # If null, conversion is done
    sub     $'0', %dl           # Convert ASCII to integer (e.g., '3' -> 3)
    imul    $10, %ax            # Multiply current %ax value by 10 (shift left)
    add     %dx, %ax            # Add the new digit to %ax
    inc     %si                 # Move to the next character in the string
    jmp     convert_loop       # Repeat the loop

convert_end:
    ret

cons_write_sector:
    movw    $prompt_current_sector, %si
    call    cons_write
    movw    current_sector, %bx
    call    cons_write_int            # Display the value in %bx
    call    cons_write_crlf
    movw    $disk_address_packet, %si # Point %si to disk_address_packet
    ret

read_sectors:
    xor     %bx, %bx     # Clear the %bx register

    movw    start_sector, %ax            # moves the value of start_sector into AX
    movw    %ax, current_sector         # moves the value of AX into current_sector
    call    cons_write_sector           # Displays the current sector 
    movw    num_sectors, %ax              # moves the value of num_sectors into AX
    add     start_sector, %ax            # Set the number of blocks to read to be num_sectors plus start_sector
    movw    %ax, 2(%si)                # Moves the value of AX into the 2nd byte of the disk address packet
    movw    $0xD000, 4(%si)           # Set the adddress to read into to be 0xD0001
    
    movw    current_sector, %bx         # moves the value of current_sector into BX
    movw    %bx, 8(%si)                # moves the value of BX into the 8th byte of the disk address packet

read_sectors_loop:

    movw    current_byte, %bx            # Moves the value of current_byte into BX
    test    $0x3F, %bx                   # Test the lower 6 bits of BX (i.e. is the current_byte a multiple of 64)
    jz      read_sectors_pause           # If the lower 6 bits are zero, pause

    movw    line_bytes, %bx            # Moves the value of current_byte into BX
    cmp     $0, %bx
    je      display_line_content         # If the lower 4 bits are zero, display the line    

read_sectors_read:
    
    movw    current_sector, %bx         # moves the value of current_sector into BX
    movw    %bx, 8(%si)                # moves the value of BX into the 8th byte of the disk address packet

    movb    $0x42, %ah                # 0x42 is the int 13h BIOS function to read the disk using LBA addressing
	movb	(boot_device), %dl        # Retrieve the ID of our boot device and put in DL	
    int     $0x13                     # Read the disk
    jc      read_failed	              # The carry flag will be set if an error occured

    incw    current_byte              # Increment the current_byte counter
    decw    line_bytes                # Increment the line_bytes counter

    jmp     read_sectors_loop         # Repeat the loop

read_sectors_done:
    movw    $prompt_finished, %si
    call    cons_writeline
    jmp     endless_loop
    ret

read_sectors_pause: 
    cmp     $0, current_byte
    je      read_sectors_continue
    
    call    cons_write_crlf
    movw    $prompt_continue, %si
    call    cons_writeline
    movw    $disk_address_packet, %si # Point %si to disk_address_packet
    movb    $0x00, %ah
    int     $0x16

read_sectors_continue:
    movw    current_byte, %bx
    cmp     $512, %bx
    je      next_sector

    incw    current_byte

    jmp     read_sectors_loop

next_sector:
    movw    current_sector, %bx
    movw    start_sector, %ax
    addw    num_sectors, %ax
    cmp     %bx, %ax
    jge     read_sectors_done

    call    cons_write_sector
    movw    $1, current_byte
    movw    $16, line_bytes
    incw    current_sector
    jmp     read_sectors_loop  


read_failed:
    xor     %si, %si
    movw 	$prompt_disk_error, %si
    call    cons_write                      # Display error messages
    xor     %bx, %bx                # Clear the %bx register
    movb    %ah, %bl
    call    cons_write_hex          # Call the subroutine to print the error code in hexadecimal
    call    cons_write_crlf         # Print a new line
	
    jmp     endless_loop

display_line_content:
    cmp     $0, current_byte
    je      read_sectors_read

    movw    4(%si), %di          # Load the address to read into (stored at 4(%si)) into %si

    movw    current_byte, %dx            # bytes per line
    # subtract 16 from %dx to get the offset
    subw    $16, %dx  
    add     %dx, %di            # Add this offset to %di

    call    display_offset       # Display the offset
    movw    $16, %cx            # Set CX to 16 (number of bytes to display)

    call   display_line_loop
    ret  

display_offset:
    movw    %dx, %bx
    call    cons_write_hex
    movb    $0x20, %al          # ASCII code for space
    call    display_char
    ret


display_line_loop:
    call    cons_write_hex_byte     # Display the byte in AL as a 2-digit hex value

    inc     %di                 # Add 1 to the value in SI
    dec     %cx               # Add 1 to the value in DX
    loop    display_line_loop   # Repeat the loop

display_line_done:
    call    cons_write_crlf     # Display a new line
    movw    $16, line_bytes      # Reset the line_bytes counter
    movw    $disk_address_packet, %si
    jmp     read_sectors_read
    ret

# Assume %al contains the byte to be displayed
cons_write_hex_byte:

    movb    (%di), %al          # Load the byte from memory into %al
    test    %al, %al            # Test if the byte is null (end of string)
    jz      display_line_done   # If null, conversion is done

    movb    %al, %bx         # Load the byte from memory into %bl
    # Display upper nibble
    call    upper_nibble_to_ascii

    # Display upper nibble
    call    lower_nibble_to_ascii

    # Use cx to count down from 16 to 0
   
    # Display a space
    movb    $0x20, %al          # ASCII code for space
    call    display_char        # Output the space character
    ret

upper_nibble_to_ascii:
    movb    %bl, %al
    shr     $4, %al             # Shift right to get the upper 4 bits
    and     $0x0F, %al          # Isolate lower 4 bits
    call    hex_char_to_ascii   # Convert to ASCII and display
    ret

lower_nibble_to_ascii:
    movb    %bl, %al
    and     $0x0F, %al          # Isolate lower 4 bits
    call    hex_char_to_ascii   # Convert to ASCII and display
    ret
    
# Subroutine to convert a 4-bit value in %al to its ASCII hex character and display it
hex_char_to_ascii:

    cmp     $10, %al            # Compare with 10
    jb      digit               # If less than 10, it's a digit

    add     $55, %al            # Convert A-F to ASCII ('A' is 65 in ASCII, 65-10 = 55)
    jmp     display_char

digit:
    add     $48, %al            # Convert 0-9 to ASCII ('0' is 48 in ASCII)

display_char:
    movb    $0x0e, %ah          # BIOS teletype service
    int     $0x10               # Call BIOS to display character
    ret

endless_loop:                   # Loop forever more
    jmp     endless_loop   


# Format of disk address packet
#
# Offset	Size	Description
#  0          1     size of packet (16 bytes)
#  1          1     always 0
#  2          2     number of sectors to transfer (max 127 on some BIOSes)
#  4          4     transfer buffer (first 2 bytes is 16-bit offset, next 2 bytes is 16 bit segment)
#  8          4     lower 32-bits of 48-bit starting LBA (starting from 0)
#  12         4     upper 16-bits of 48-bit starting LBA (will always be 0 for us)


disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0

# ... data section ...

prompt_start_sector: .string "Enter starting sector (4 Digits): "
prompt_num_sectors: .string "Enter number of sectors (4 Digits): "
prompt_no_input: .string "No input detected. Please try again: "
prompt_current_sector: .string "Current sector: "
IntBuffer:   .string "     "
prompt_disk_error: .string "Disk read error occurred. Error code: "
prompt_invalid_input: .string "Invalid input. Please try again."
prompt_continue: .string "Press any key to continue..."
debug_msg: .string "Returned from input loop."
prompt_finished: .string "Finished reading sectors."

start_sector: .word 0x0000 # Allocates 2 bytes, initialized to 0
line_bytes: .word 0x0000 # Allocates 2 bytes, initialized to 0
current_byte: .word 0x0000  
total_bytes: .word 0x0000  
num_sectors: .word 0x0000 # Allocates 2 bytes, initialized to 0
current_sector: .word 0x0000 # Allocates 2 bytes, initialized to 0

input_buffer: .space 5, 0
max_input_amount: .byte 0
input_length: .byte 0
read_buffer: .space 512 

# Program data

boot_device:
    .byte   0

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"

