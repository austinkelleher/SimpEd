.eqv MAX_FILE_BYTES	4096
.eqv FILE_PATH_MAX_LEN	1024
.eqv NEW_LINE_CHAR	10
.eqv SPACE_CHAR		32
.eqv DOLLAR_CHAR	36
.eqv Y_CHAR		121
.eqv MAX_LINE_CHARS	120
.eqv MAX_USERNAME_LEN	20

.data	
	editorMenuPrompt:	.asciiz 	"Edit Line (y/n):\n"
	lineNumberPrompt:	.asciiz 	"Please enter a line number to edit:\n"
	filePathPrompt:		.asciiz 	"Please enter a file path:\n"
	fileNotFoundErrorMsg:	.asciiz  	"Error: File not found\n"
	fileSavedMessage:	.asciiz 	"The file has been saved:\n"
	invalidLineMsg:		.asciiz 	"Error: Invalid line.\n"
	usernamePrompt:		.asciiz 	"Please enter your username: "
	filePath: 		.space 		FILE_PATH_MAX_LEN
	usernameBuffer:		.space		MAX_USERNAME_LEN
	fileLoadBuffer: 	.byte 		0 : MAX_FILE_BYTES
	parsedFile:		.byte 		0 : MAX_FILE_BYTES
	fileIdBuffer:		.byte 		0 : 6
	fileDescriptor:		.word 		0
	totalLineCount:		.word 		0
	editLineNumber:		.word 		0

.text
main:
	la $a1,  usernameBuffer				# Load the address of the buffer to store the user's username in
	jal LoginUser
	jal RemoveUsernameNewLineChar			# When using syscall 8, we get a new line char at the end of the input by default
							# We want to remove this, so we can easily access string at any time
	
	PostLogin:					# The main loop that happens after the user logs in
		jal GetFilePathPrompt			# Ask the user for the file path
		
		la $a0, usernameBuffer
		jal PrintBashShell
		
		la $a0, filePath
		la $a1, FILE_PATH_MAX_LEN
		jal GetFile				# Attempt to obtain the file that the user requested
		
		la $a0, filePath			# Load File Nam
		la $a3, fileDescriptor
		jal OpenFile
		
		lw $a0, fileDescriptor			# Load file descriptor 
		la $a1, fileLoadBuffer			# Load Buffer Address
		li $a2, MAX_FILE_BYTES
		jal ReadFile
		
		lw $a0, fileDescriptor
		jal CloseFile				# Close the open file
		
		la $a0, fileLoadBuffer
		la $a1, parsedFile
		la $a2, totalLineCount
		jal ParseFileContents			# Read the contents of the file and store the data properly
		
		la $a0, totalLineCount
		la $a1, parsedFile
		jal PrintLines				# Print out the file if it was found
		
		li $a0, NEW_LINE_CHAR			# Print new line
		li $v0, 11
		syscall
		
		la $a0, editorMenuPrompt		# Print the editor menu options
		li $v0, 4		
		syscall
		
		la $a0, usernameBuffer
		jal PrintBashShell
		
		li $v0, 12				# Ask the user whether or not they want to edit the file - Get char (y/n)
		syscall

		bne $v0, Y_CHAR, Finish			# If the answer was anything but 'y', quit
		
		jal PrintNewLineChar
		
		la $a0, lineNumberPrompt		# Print line number prompt
		li $v0, 4
		syscall
		
		la $a0, usernameBuffer
		jal PrintBashShell
		
		la $a0, parsedFile			# Load the file contents
		jal LineEditRequest			# Ask the user which line they want to edit
		
		la $a0, filePath			# Load File Name
		la $a1, parsedFile
		la $a2, fileDescriptor
		jal WriteFile				# Save the file after writing
		
		jal CloseFile				# Close the file
		
		la $a0, fileSavedMessage		# Print file saved message
		li $v0, 4
		syscall
		
		la $a0, totalLineCount
		la $a1, parsedFile
		jal PrintLines				# Print newly saved file
		
		Finish:
			jal PrintNewLineChar
			j PostLogin

####################################################
# Prints the bash shell
# 
# Arguments:
#	$a0 - Address to the parsed file
# Used temp registers:
# 	$t0 - Line number user inputs
#	$t1 - Max number of characters in a line
####################################################	
LineEditRequest:	
	li $v0, 5				# Get the line number
	syscall
	
	blt $v0, 1, InvalidLineError		# Files always start at 1 line
	lw $t3, totalLineCount
	bgt $v0, $t3, InvalidLineError		# The user must enter in a line less than or equal to the total line count
	
	subi $v0, $v0, 1			# Array starts at 0, so substract 1 from input
	move $t0, $v0				# Put the line number input in $t0
	mul $t0, $t0, MAX_LINE_CHARS

	add $a0, $a0, $t0			# Beginning address of file + jump offset (MAX_LINE_CHARS * line number-1)
	
	li $t1, MAX_LINE_CHARS
	sub $t1, $t1, 1
	
	move $a1, $t1				# Max number of characters. Preserve new line at end of line.
	li $v0, 8
	syscall
	
	jr $ra
	
####################################################
# Prepares buffer data to be written to a file
#
# Arguments:
#	$a0 - File path
#	$a1 - The parsed file
#	$a2 - File descriptor
#
# Temp registers used:
# 	$t0 - Destination pointer parsed file
# 	$t1 - Line start pointer parsed
# 	$t2 - Current character
# 	$t3 - Total line count
# 	$t4 - Column counter
# 	$t5 - Source pointer
# 	$t6 - Byte counter
####################################################
WriteFile:
	li $t6, 0
	lw $t3, totalLineCount
	la $t0, parsedFile
	la $t1, parsedFile
	li $t4, 0
	
	WriteFileLoop:
		add $t5, $t1, $t4			# source_pointer = line start + column
		lb $t2, ($t5)				# Get current character from file
		sb $t2, ($t0)				# Store current character in destination
	
		addi $t6, $t6, 1			# Increment byte counter
		addi $t4, $t4, 1			# Increment column
		addi $t0, $t0, 1			# Increment to next character address
	
		bne $t2, 10, NotNewLineWrite		# If not equal to newline
	
		addi $t1, $t1, MAX_LINE_CHARS		# Increment row
		li $t4, 0				# Reset column counter
		subi $t3, $t3, 1			# Decrement line count
	
	NotNewLineWrite:
		bne $t2, 0, WriteFileLoop
		sb $0, ($t0)				# Store null-terminator to end of file
		
		subi $t6, $t6, 1			# Decrement character counter by one because of off by 1
		
		move $t7, $a1				# Move parsed file to temporary register
		move $t8, $a2				# Move file descriptor to temporary register
		
		li	$v0, 13				# Open File Syscall
		li	$a1, 1				# Write Flag
		li	$a2, 0				# (ignored)
		syscall
		
		move $a2, $t8				# Restore file descriptor
		sw $v0, ($a2)				# Store the file descriptor
		lw $a0, ($a2)				# Load the file descriptor
		move $a1, $t7				# Restore parsed file
		move $a2, $t6				# Move total number of bytes to save to file
		li $v0, 15				# Write file syscall
		syscall
	
		jr $ra

####################################################
# Prepares buffer data to be written to a file
#
# Arguments:
#	$a0 - File load buffer address
#	$a1 - The parsed file address
#	$a2 - Total line count address
#
# Temporary registers used:
# 	$t0 - Loaded character
# 	$t1 - File load buffer
# 	$t2 - Line offset
# 	$t3 - Column offset
# 	$t4 - Address to beginning of parsed file
# 	$t5 - Address of destination inside file (address to put character)
# 	$t6 - Line counter
####################################################
ParseFileContents:
	li $t0, 0					# Initialize current character
	move $t1, $a0
	li $t2, 0					# Initialize line offset
	li $t3, 0					# Initialize column offset
	move $t4, $a1
	li $t5, 0					# Initialize $t4 + $t3 + $t2
	li $t6, 1					# Line counter
	li $t7, 0					# Byte counter
	
	ParseFileLoop:
		lb $t0, ($t1)
		add $t5, $t4, $t3		
		add $t5, $t5, $t2			# $t5 contains address to put character
		sb $t0, ($t5)				# Store character in destination address
		
		addi $t3, $t3, 1			# Increment column counter

		beqz $t0, finParse			# Check for null terminator
		bne $t0, 10, NotNewLine			# Check if the destination address is the null character
	
		addi $t6, $t6, 1			# New line, increment number of new lines
		addi $t2, $t2, MAX_LINE_CHARS		# Increment line offset by maximum number of characters on a line, MAX_LINE_CHARS
		li $t3, 0
		
	NotNewLine:
		addi $t1, $t1, 1
		j ParseFileLoop				# Increment to next character
	
	finParse:
		sw $t6, ($a2)				# Store the line count into data memory
		jr $ra

####################################################
# Prepares buffer data to be written to a file
#
# Arguments:
#	$a0 - Total line count address
#	$a1 - The parsed file address
#
# Temporary registers used:
# 	$t0 - Line count
#	$t1 - Total line count
#	$t2 - Parsed file address
####################################################	
PrintLines:
	li $t0,	1					# Line count
	lb $t1, ($a0)					# Move total line count into temporary register
	move $t2, $a1					# Move parsed file into temporary register
	
	LinePrintLoop:
		move $a0, $t0				# Print the line number
		li $v0, 1
		syscall
		
		la $a0, SPACE_CHAR			# Space character load
		li $v0, 11
		syscall
	
		move $a0, $t2				# Move parsed file to print string register $a0		
		li $v0, 4
		syscall
	
		addi $t2, $t2, MAX_LINE_CHARS		# Next line
		addi $t0, $t0, 1
	
		ble $t0, $t1, LinePrintLoop		# Line count is not equal to total lines
	
		jr $ra

####################################################
# Prints an invalid line error
# Arguments:
#	$a0 - File path buffer
#	$a1 - File buffer size
####################################################
GetFile:
	li $v0, 8					# Read the file path from the user
	syscall
	
	findNewLine:					# We do not want to store a new line character, so first find
		addi $a0, $a0, 1			# the position in which it was stored by syscall 8
		lb $a1, 0($a0)
		bne $a1, 10, findNewLine
	
	sb $0, ($a0)					# Store a null terminated character instead of the new line
	
	jr $ra

####################################################
# Opens a file
#
# Arguments:
#	$a0 - File path
#	$a3 - File descriptor
####################################################
OpenFile:
	li	$v0, 13				# Open File Syscall
	li	$a1, 0				# Read-only Flag
	li	$a2, 0				# (ignored)
	syscall
	
	blt	$v0, 0, fileNotFoundError	# Goto Error
	
	sw 	$v0, ($a3)
	jr $ra
	
####################################################
# Reads file data and stores into a buffer
#
# Arguments:
#	$a0 - File Descriptor
#	$a1 - File buffer address
#	$a2 - Maximum file byte size
####################################################
ReadFile:
	li $v0, 14					# Read File Syscall
	syscall
	
	jr $ra

####################################################
# Closes a file
#
# Arguments:
#	$a0 - File Descriptor
####################################################	
CloseFile:
	li $v0, 16
	syscall
	
	jr $ra

####################################################
# Prints when a file is not found
####################################################	
fileNotFoundError:
	la $a0, fileNotFoundErrorMsg
	li $v0, 4
	syscall
	
	j PostLogin

####################################################
# Prints the bash shell
# Arguments:
# 	$a0 - Address to the username
####################################################		
PrintBashShell:
	li $v0, 4
	syscall
	
	li $a0, DOLLAR_CHAR				# Print dollar char
	li $v0, 11
	syscall
	
	li $a0, SPACE_CHAR				# Print dollar char
	li $v0, 11
	syscall
	
	jr $ra

####################################################
# Asks for the user's username and stores it into a buffer
# Arguments:
# 	$a1 - Buffer to store the username in
####################################################	
LoginUser:
	la $a0, usernamePrompt
	li $v0, 4
	syscall
	
	move $a0, $a1					# Move buffer to correct register
	la $a1, MAX_USERNAME_LEN
	li $v0, 8					# Read string
	syscall
	
	jr $ra

####################################################
# Removes the new line character from the username buffer
####################################################	
RemoveUsernameNewLineChar:
	li $t0, 0        				# Set index to 0
	remove:
    		lb $t1, usernameBuffer($t0)    		# Load character at index
    		addi $t0, $t0, 1      			# Increment index
    		bnez $t1, remove    		 	# Loop until the end of string is reached
    		beq $a1, $t0, skip    		 	# Do not remove \n when string = maxlength
    		subiu $t0, $t0, 2     			# If above not true, Backtrack index to '\n'
    		sb $0, usernameBuffer($t0)    		# Add the terminating character in its place
    		jr $ra
	skip:
		jr $ra
		
####################################################
# Prints an invalid line error
####################################################	
InvalidLineError:
	la $a0, invalidLineMsg				# Print invalid message error
	li $v0, 4
	syscall
	
	la $a0, lineNumberPrompt			# Print line number prompt
	li $v0, 4
	syscall
	
	j LineEditRequest
		
####################################################
# Prints a new line character
####################################################		
PrintNewLineChar:
	li $a0, NEW_LINE_CHAR
	li $v0, 11
	syscall
	
	jr $ra

####################################################
# Displays the prompt to request the file path
####################################################	
GetFilePathPrompt:
	la $a0, filePathPrompt
	li $v0, 4
	syscall
	
	jr $ra

####################################################
# Quit the program using syscall 10
####################################################
EndProgram:
	li $v0, 10
	syscall

