#!/bin/bash
# The purpose of this script is to easily set a timer (using gnome-clocks) so that students
# can visually see how much time is left in a lab or break. This script assumes that the 
# machine which this is being run from is displaying seconds with the time. This can done
# by running "gsettings set org.gnome.desktop.interface clock-show-seconds true" or by 
# using gnome-tweak-tool. There are two basic ways to run this script:
# Method 1: ./timer.sh 15 - This method will set the timer to 15 minutes.
# Method 2: ./timer.sh 2:40 - This method sets the timer to end at 2:40.
# Copy timer.sh into /usr/local/bin if you want to just use: timer.sh 2:40
# EXAMPLE: The current time is 12:53:22 and the instructor runs: ./timer.sh 1:10
# 22 seconds will round up to 25 seconds giving 16 minutes and 35 seconds until the
# timer should go off. The DELAY will then subtract additional time (possibly 10
# seconds for VT classes). If DELAY=10, then the timer will be configured to show
# 16 minutes 25 seconds. This means that the instructor should start the timer when the
# time is exactly 12:53:35 (or 12 seconds after running ./timer.sh 1:10). On a RHEL 7 
# machine, the instructor will need to select the "timer" button of gnome-clocks
# before being able to start the timer.
# NOTE: If the VT environment is sluggish, a 10-second delay may not be enough time
# to click the "timer" button of gnome-clocks and start the timer. If this is the 
# case, simply increase the DELAY variable in increments of 5 seconds.
VIRTUAL_DELAY=10
PHYSICAL_DELAY=5

# Exit Status Codes:
# 1 - More than one possitional parameter or used -h or --help
# 2 - User input doesn't appear to be a valid time.
# 3 - The hour field wasn't specified or isn't between 0-23.
# 4 - The minute field wasn't specified or isn't between 0-59.
# 5 - Something went wrong with calculating minutes.

# Check to see if any positional parameters were entered
if [ $# -eq 0 ]; then
	# No positional parameters were entered, so prompt for it.
	until [ -n "$USER_INPUT" ]; do
		read -p "Enter an end time or the number of minutes: " USER_INPUT
	done
elif [ $# -eq 1 ]; then
	if [ $1 = "-h" ] || [ $1 = "--help" ]; then
		echo "Syntax: $0 minutes|time" 1>&2
		echo "Example: $0 15 (sets the timer to 15 mintues)"
		echo "Example: $0 2:40 (sets the timer to end at 2:40)"
		exit 1
	else
		USER_INPUT=$1
	fi
else
	# More than one positional parameter was entered. Display a syntax message.
	echo "Syntax: $0 minutes|time" 1>&2
	echo "Example: $0 15 (sets the timer to 15 mintues)"
	echo "Example: $0 2:40 (sets the timer to end at 2:40)"
	exit 1
fi

# Validate that user input is a time or minutes
echo $USER_INPUT | grep -q ":"
if [ $? -eq 0 ]; then
	# $USER_INPUT included a colon, so it must be a time.
	# For the first colon-delimited field in $USER_INPUT (the hour filed), check to see if there is
	# something before the hour, the hour itself, and something after the hour.
	# For some reason I had problems performing math operations on numbers such as 06, so I stripped
	# the first leading 0 from the hour an minute fields (if it existed). I'm guessing that 06 was
	# being treated as a string rather than a number.
	MISC_HOUR_START=$(echo $USER_INPUT | cut -d: -f1 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\)\(.*\)/\1/')
	TEMP_HOUR=$(echo $USER_INPUT | cut -d: -f1 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\).*/\2/' | sed 's/^0\([0-9]\)/\1/')
	MISC_HOUR_END=$(echo $USER_INPUT | cut -d: -f1 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\)\(.*\)/\3/')

	# For the second colon-delimited field in $USER_INPUT (the minute filed), check to see if there is
	# something before the minute, the minute itself, and something after the minute (possibly am or pm).
	MISC_MIN_START=$(echo $USER_INPUT | cut -d: -f2 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\)\(.*\)/\1/')
	TEMP_MIN=$(echo $USER_INPUT | cut -d: -f2 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\).*/\2/' | sed 's/^0\([0-9]\)/\1/')
	AM_PM=$(echo $USER_INPUT | cut -d: -f2 | sed 's/^\([^[:digit:]]*\)\([[:digit:]]\+\)\(.*\)/\3/')
	
	if [ -n "$MISC_HOUR_START" ] || [ -n "$MISC_HOUR_END" ] || [ -n "$MISC_MIN_START" ]; then
		# Something besides digits were added in the hour or minute fields.
		# I don't care about something after the minute field as it could be am or pm.
		echo "$USER_INPUT doesn't appear to be a valid time." 1>&2
		exit 2
	fi

	# Verify the hour field.
	if [ -z "$TEMP_HOUR" ]; then	
		# $TEMP_HOUR hasn't been set.
		echo "$USER_INPUT doesn't appear to be a valid time." 1>&2
		exit 3
	else 
		# Verify that the hour is between 0 and 23
		if [ $TEMP_HOUR -ge 0 ] && [ $TEMP_HOUR -le 23 ]; then
			# Convert hour to 12-hour format
			if [ $TEMP_HOUR -gt 12 ]; then
				END_HOUR=$[ $TEMP_HOUR - 12 ]
			elif [ $TEMP_HOUR -eq 0 ]; then
				END_HOUR=12
			else
				END_HOUR=$TEMP_HOUR
			fi
		else
			# The hour is out of range.
			echo "$TEMP_HOUR does not appear to be valid." 1>&2
			exit 3
		fi
	fi

	# Verify the minute field.
	if [ -z "$TEMP_MIN" ]; then	
		# $TEMP_MIN hasn't been set.
		echo "$USER_INPUT doesn't appear to be a valid time." 1>&2
		exit 4
	else 
		if [ $TEMP_MIN -ge 0 ] && [ $TEMP_MIN -le 59 ]; then
			END_MIN=$TEMP_MIN
		else
			# The minute is out of range.
			echo "$TEMP_MIN does not appear to be valid." 1>&2
			exit 4
		fi
	fi

	# I had to strip out the leading 0 (if it existed) because of problems I was
	# having doing math on a minute such as 06.
	CURRENT_HOUR=$(date +%I | sed 's/^0\([1-9]\)/\1/')
	CURRENT_MIN=$(date +%M | sed 's/^0\([1-9]\)/\1/')

	# I am subtracting 1 minute and will later compensate with the appropriate number of seconds.
	# For example, if the current time is 12:20 and I set the timer for 12:30, the timer will
	# ultimately be 9 minutes plux X seconds.
	if [ $END_MIN -eq $CURRENT_MIN ]; then
		# Example: ending time = 2:20 and current time = 1:20
		# END_MIN=20 & CURRENT_MIN=20
		ADD_MIN=59
		NEXT_HOUR=yes
	elif [ $END_MIN -gt $CURRENT_MIN ]; then
		# Example: ending time = 1:55 and current time = 1:50
		# END_MIN=55 & CURRENT_MIN=50
		ADD_MIN=$[ $END_MIN - $CURRENT_MIN - 1 ]
		NEXT_HOUR=no
	elif [ $END_MIN -lt $CURRENT_MIN ]; then
		# Example: ending time = 2:05 and current time = 1:50
		# END_MIN=5 & CURRENT_MIN=50
		ADD_MIN=$[ 60 - $CURRENT_MIN + $END_MIN - 1 ]
		NEXT_HOUR=yes
	else
		echo "Something appears wrong with \$END_MIN ($END_MIN) or \$CURRENT_MIN ($CURRENT_MIN)." 1>&2
		exit 5
	fi

	if [ $END_HOUR -eq $CURRENT_HOUR ]; then
		# Example: ending time = 1:55 and current time = 1:50
		# END_HOUR=1 & CURRENT_HOUR=1
		ADD_HOUR=0
	elif [ $END_HOUR -gt $CURRENT_HOUR ]; then
		# Example: ending time = 2:20 and current time = 1:50
		# END_HOUR=2 & CURRENT_HOUR=1
		TEMP_END_HOUR=$[ $END_HOUR - $CURRENT_HOUR ]
		if [ $NEXT_HOUR = "yes" ]; then
			ADD_HOUR=$[ $TEMP_END_HOUR - 1 ]
		else
			ADD_HOUR=$TEMP_END_HOUR
		fi
	elif [ $END_HOUR -lt $CURRENT_HOUR ]; then
		# Example: ending time = 1:20 and current time = 12:50
		# END_HOUR=1 & CURRENT_HOUR=12
		TEMP_24HOUR=$[ $END_HOUR + 12 ]
		TEMP_END_HOUR=$[ $TEMP_24HOUR - $CURRENT_HOUR ]
		if [ $NEXT_HOUR = "yes" ]; then
			ADD_HOUR=$[ $TEMP_END_HOUR - 1 ]
		else
			ADD_HOUR=$TEMP_END_HOUR
		fi
	else
		echo "Something appears wrong with \$END_HOUR ($END_HOUR) or \$CURRENT_HOUR ($CURRENT_HOUR)." 1>&2
		exit 5
	fi

	# I had to strip out the leading 0 (if it existed) because of problems I was
	# having doing math on a second such as 06.
	CURRENT_SECOND=$(date +%S | sed 's/^0\([0-9]\)/\1/')
	# This case statement will round up to the nearest 5-second increment.
	case $CURRENT_SECOND in
		0|1|2|3|4|5)
			CURRENT_SECOND=5
		;;
		6|7|8|9|10)
			CURRENT_SECOND=10
		;;
		11|12|13|14|15)
			CURRENT_SECOND=15
		;;
		16|17|18|19|20)
			CURRENT_SECOND=20
		;;
		21|22|23|24|25)
			CURRENT_SECOND=25
		;;
		26|27|28|29|30)
			CURRENT_SECOND=30
		;;
		31|32|33|34|35)
			CURRENT_SECOND=35
		;;
		36|37|38|39|40)
			CURRENT_SECOND=40
		;;
		41|42|43|44|45)
			CURRENT_SECOND=45
		;;
		46|47|48|49|50)
			CURRENT_SECOND=50
		;;
		51|52|53|54|55)
			CURRENT_SECOND=55
		;;
		56|57|58|59)
			CURRENT_SECOND=60
		;;
	esac

	# The purpose of DELAY is to give the instructor a little bit of time
	# before he or she needs to start the timer. For gnome-clocks in RHEL 7,
	# the instructor will first need to click to the timer tab. For the most
	# exact results, you should display seconds on the classroom machine.
	# This can be accomplished by running "gnome-tweak-tool" as the logged in user.
	# Alternatively: gsettings set org.gnome.desktop.interface clock-show-seconds true
	# The above case statement will also round up to the nearest 5-second multiple.
	# So, if the current time is 12:53:22 and I run "./timer.sh 1:10", 22 seconds will
	# round up to 25 seconds giving me 16 minutes and 35 seconds until the timer
	# should go off. The DELAY will then subtract some more time (possibly 10 
	# seconds for a VT class). So the timer will be configured to show 16 minutes 
	# 25 seconds. This means that the instructor should start the timer when the 
	# time is exactly 12:53:35. 
	
	# Virtual machines probably need more of a delay than physical machines.
	echo $(hostname -s) | grep -q -E 'classroom|desktop|server'
	if [ $? -eq 0 ]; then
		DELAY=$VIRTUAL_DELAY
	else
		DELAY=$PHYSICAL_DELAY
	fi
	TEMP_SECOND=$[ 60 - $CURRENT_SECOND - $DELAY ]

	ADD_TIME=$[ $[ $ADD_MIN * 60 ] + $TEMP_SECOND ]
	gsettings set org.gnome.clocks timer $ADD_TIME
	gnome-clocks &

	# I had problems when I tried to set the timer to over 1 hour using
	# gsettings. If the timer is for 1 hour or longer, the instructor will
	# need to manually increment the hour field in gnome-clocks. Running
	# "gsettings list-recursively org.gnome.clocks" results in
	# "org.gnome.clocks timer uint32 300" (the last value could of course
	# be different based on the last time this script was used). I don't 
	# know what "uint32" means, but it wasn't happy with a value >= 3600.
	if [ $ADD_HOUR -gt 0 ]; then
		echo "==================================="
		echo "Add $ADD_HOUR hour(s) to the timer."
		echo "==================================="
	fi
else
	# Verify that only a number was entered
	echo "$USER_INPUT" | grep -qv "[[:digit:]]"
	if [ $? -eq 0 ]; then
		echo "Example: $0 15 (sets the timer to 15 mintues)"
		echo "Example: $0 2:40 (sets the timer to end at 2:40)"
		exit 1
	fi

	# Check to see how many minutes to add.
	EXTRACTED_MIN=$(echo $USER_INPUT | sed 's/^\([[:digit:]]\+\).*/\1/')
	ADD_HOUR=0
	TEMP_MIN=$EXTRACTED_MIN
	if [ $TEMP_MIN -gt 60 ]; then
		until [ $TEMP_MIN -lt 60 ]; do
			TEMP_MIN=$[ $TEMP_MIN - 60 ]
			ADD_HOUR=$[ $ADD_HOUR + 1 ]
		done
	fi
	ADD_MIN=$TEMP_MIN

	ADD_TIME=$[ $ADD_MIN * 60 ]
	gsettings set org.gnome.clocks timer $ADD_TIME
	gnome-clocks &

	# I had problems when I tried to set the timer to over 1 hour using
	# gsettings. If the timer is for 1 hour or longer, the instructor will
	# need to manually increment the hour field in gnome-clocks. Running
	# "gsettings list-recursively org.gnome.clocks" results in
	# "org.gnome.clocks timer uint32 300" (the last value could of course
	# be different based on the last time this script was used). I don't 
	# know what "uint32" means, but it wasn't happy with a value >= 3600.
	if [ $ADD_HOUR -gt 0 ]; then
		echo "==================================="
		echo "Add $ADD_HOUR hour(s) to the timer."
		echo "==================================="
	fi
fi
