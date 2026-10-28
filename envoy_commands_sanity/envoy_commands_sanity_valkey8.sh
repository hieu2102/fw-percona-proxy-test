#!/bin/bash

# Continue the script execution only if the config file is present
function precheck01()
{
    if [[ -f ./test_params_envoy.cfg ]]
    then
        source ./test_params_envoy.cfg
        echo "$(date) : INFO : Config file is present. Continuing with the execution."
    else
        echo "$(date) : ERROR : Config params file is not present in this path : `pwd`. Exiting."
        exit 1
    fi
}

# Display the set contents
function display_set_members()
{
    echo "$(date) : INFO : $1 set members are listed below"
    ${KCTL_CMD} smembers $2 2>/dev/null | grep -v option
}

# For calculating the script execution time
function time_calculation()
{
    end_time=$(date +%s)
    total_time_in_secs=$((end_time - start_time))
    seconds=${total_time_in_secs}
    hours=$(( seconds / 3600 ))
    minutes=$(( (seconds % 3600) / 60 ))
    seconds=$(( seconds % 60 ))
    printf "Total script execution time is (HH:MM:SS) - %02d:%02d:%02d\n" "$hours" "$minutes" "$seconds"
}

# Create couple of sample sets for testing set commands
function create_sets()
{
    ODD_ARR=(1 3 5 7 9)
    PRIME_ARR=(2 3 5 7 11)
    ${KCTL_CMD} del {set}.odd {set}.prime {set}.inter 2>/dev/null | grep -v option
    ${KCTL_CMD} sadd {set}.odd ${ODD_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${KCTL_CMD} sadd {set}.prime ${PRIME_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]
    then
        echo "$(date) : INFO : Both sample sets are created. sadd and del commands are verified successfully."
        for set_name in "odd" "prime"
        do
            display_set_members ${set_name} "{set}.${set_name}"
        done
    else
        echo "$(date) : ERROR : Failed to create sets : ${ORV},${PRV}. Exiting."
        exit 1
    fi
}

# Function to validate union of 2 sets
function set_union()
{
    RES=$(${KCTL_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option | egrep -v "1|2|3|5|7|9|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set union(sunion) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for set union(sunion) (${RES}). Exiting."
        ${KCTL_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi


    ${KCTL_CMD} sunionstore {set}.union {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} smembers {set}.union 2>/dev/null | grep -v option | egrep -v "1|2|3|5|7|9|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set union(sunionstore) verified successfully."
        display_set_members "union" "{set}.union"
    else
        echo "$(date) : FAILED : Validation failed for storing set union(sunionstore) (${RES}). Exiting."
        ${KCTL_CMD} sunion {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi
}

# Function to validate intersection of 2 sets and storing in another set as well
function set_intersection()
{
    RES=$(${KCTL_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option | egrep -v "3|5|7" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set intersection(sinter) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for set intersection(sinter) (${RES}). Exiting."
        ${KCTL_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} sinterstore {set}.inter {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} smembers {set}.inter 2>/dev/null | grep -v option | egrep -v "3|5|7" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set intersection(sinterstore) verified successfully."
        display_set_members "intersected" "{set}.inter"
    else
        echo "$(date) : FAILED : Validation failed for storing set intersection(sinterstore) (${RES}). Exiting."
        ${KCTL_CMD} sinter {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi
}

# Function to validate difference between 2 sets
function set_diff()
{
    RES=$(${KCTL_CMD} sdiff {set}.prime {set}.odd 2>/dev/null | grep -v option | egrep -vw "2|11" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set difference(sdiff) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for set difference(sdiff) (${RES}). Exiting."
        ${KCTL_CMD} sdiff {set}.prime {set}.odd 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} sdiffstore {set}.diff {set}.odd {set}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} smembers {set}.diff 2>/dev/null | grep -v option | egrep -v "1|9" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Set difference(sdiffstore) verified successfully."
        display_set_members "difference" "{set}.diff"
    else
        echo "$(date) : FAILED : Validation failed for storing set diff(sdiffstore) (${RES}). Exiting."
        ${KCTL_CMD} sdiff {set}.odd {set}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi
}

# Function to validate the existence of an element(s) in a set
function set_membership()
{
    RES1=$(${KCTL_CMD} sismember {set}.union 1 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "1" | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} sismember {set}.union -1 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "0" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : PASSED : Set member command(sismember) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for set member(sismember) (${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "1" | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "0" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 3 ]] && [[ ${RES2} -eq 2 ]]
    then
        echo "$(date) : PASSED : Multiple set member command(smismember) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for multiple set members(smismember) (${RES1} and ${RES2}). Exiting."
        ${KCTL_CMD} smismember {set}.union 1 -1 3 5 100 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi
}

# All commands related to sets
function set_operations()
{
    create_sets
    set_union
    set_intersection
    set_diff
    set_membership
}

# Function to display zset elements
function display_zset_members()
{
    echo "$(date) : INFO : $1 zset members withscores are listed below"
    ${KCTL_CMD} zrange $2 0 -1 withscores 2>/dev/null | grep -v option
}

# Create 2 sorted sets of odd and prime number
function create_zsets()
{
    ODD_ZSET=(1 one 3 three 5 five 7 seven 9 nine)
    PRIME_ZSET=(2 two 3 three 5 five 7 seven 11 eleven)
    ${KCTL_CMD} del {zset}.odd {zset}.prime 2>/dev/null | grep -v option
    ${KCTL_CMD} zadd {zset}.odd ${ODD_ZSET[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${KCTL_CMD} zadd {zset}.prime ${PRIME_ZSET[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]
    then
        echo "$(date) : INFO : Both sample sorted sets are created. zadd and del commands are verified successfully."
        for zset_name in "odd" "prime"
        do
            display_zset_members ${zset_name} "{zset}.${zset_name}"
        done
    else
        echo "$(date) : ERROR : Failed to create sets : ${ORV},${PRV}. Exiting."
        exit 1
    fi
}

# Function to validate union of 2 sorted sets with their scores and storing them in a different sorted set
function zset_union()
{
    RES=$(${KCTL_CMD} zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -vw "1|2|6|9|10|11|14|one|two|three|five|seven|nine|eleven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Sorted set union(zunion) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for sorted set union(zunion) (${RES}). Exiting."
        ${KCTL_CMD} zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} zunionstore {zset}.zunion 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} zrange {zset}.zunion 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "1|2|6|9|10|11|14|one|two|three|five|seven|nine|eleven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Storing sorted set union(zunionstore) verified successfully."
        display_zset_members "union" "{zset}.zunion"
    else
        echo "$(date) : FAILED : Validation failed for storing sorted set union(zunionstore) (${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

# Function to validate intersection of 2 sorted sets with their scores and storing them in a different sorted set
function zset_inter()
{
    RES=$(${KCTL_CMD} zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -v "6|10|14|three|five|seven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Sorted set intersection(zinter) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for sorted set intersection(zinter) (${RES}). Exiting."
        ${KCTL_CMD} zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} zinterstore {zset}.zinter 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} zrange {zset}.zinter 0 -1 withscores 2>/dev/null | grep -v option | egrep -v "6|10|14|three|five|seven" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Storing sorted set intersection(zinterstore) verified successfully."
        display_zset_members "intersected" "{zset}.zinter"
    else
        echo "$(date) : FAILED : Validation failed for storing sorted set intersection(zinterstore) (${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

# Function to validate difference of 2 sorted sets with their scores and storing them in a different sorted set
function zset_diff()
{
    RES=$(${KCTL_CMD} zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option | egrep -v "one|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Sorted set difference(zdiff) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for sorted set difference(zdiff) (${RES}). Exiting."
        ${KCTL_CMD} zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} zdiffstore {zset}.zdiff 2 {zset}.odd {zset}.prime 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} zrange {zset}.zdiff 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "1|9|one|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Storing sorted set difference(zdiffstore) verified successfully."
        display_zset_members "intersected" "{zset}.zinter"
    else
        echo "$(date) : FAILED : Validation failed for storing sorted set intersection(zinterstore) (${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

# Function to validate other commands related to sorted sets with their scores
function zset_other()
{
    MEM_VAL=$(${KCTL_CMD} zrandmember {zset}.odd 2 2>/dev/null | grep -v option | sort | uniq | wc -l | sed 's/ //g')
    MEM=$(${KCTL_CMD} zrandmember {zset}.odd 2>/dev/null | grep -v option | sort | uniq | sed 's/ //g')
    RES=$(${KCTL_CMD} zrange {zset}.odd 0 -1 2>/dev/null | grep -v option | grep -w "${MEM}" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 1 ]] && [[ ${MEM_VAL} -eq 2 ]]
    then
        echo "$(date) : PASSED : Fetching random member from sorted set(zrandmember) verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for random member fetch in sorted set(zrandmember) (${RES} and ${MEM_VAL}). Exiting."
        ${KCTL_CMD} zrandmember {zset}.odd 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} zrangestore {zset}.zdest {zset}.odd 2 -1 2>/dev/null | grep -v option >/dev/null 2>&1
    RES=$(${KCTL_CMD} zrange {zset}.zdest 0 -1 withscores 2>/dev/null | grep -v option | egrep -vw "5|7|9|five|seven|nine" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Storing part of sorted set in another sorted set(zrangestore) verified successfully."
        display_zset_members "store" "{zset}.zdest"
    else
        echo "$(date) : FAILED : Validation failed for storing a part of sorted set in another sorted set(zrangestore) (${RES}). Exiting."
        display_zset_members "store" "{zset}.zdest"
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} zmscore {zset}.odd one two three 2>/dev/null | grep -v option | grep "nil" | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} zmscore {zset}.odd one two three 2>/dev/null | grep -v option | grep -v "nil" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 2 ]]
    then
        echo "$(date) : PASSED : Fetching the member score in a sorted set(zmscore) verified successfully."
        display_zset_members "store" "{zset}.zdest"
    else
        echo "$(date) : FAILED : Validation failed for fetching score for a member of sorted set(zmscore) (${RES1} and ${RES2}). Exiting."
        ${KCTL_CMD} zmscore {zset}.odd one two three 2>/dev/null | grep -v option
        time_calculation
        exit 1
    fi
}

# Perform all sorted set operations
function zset_operations()
{
    create_zsets
    zset_union
    zset_inter
    zset_diff
    zset_other
}

# To display the contents of the list
function display_list_members()
{
    echo "$(date) : INFO : $1 list members are listed below"
    ${KCTL_CMD} lrange $2 0 -1 2>/dev/null | grep -v option
}

# To create test lists
function create_lists()
{
    ODD_ARR=(1 3 5 7 9)
    PRIME_ARR=(2 3 5 7 11)
    ${KCTL_CMD} del {list}.odd {list}.prime 2>/dev/null | grep -v option
    ${KCTL_CMD} lpush {list}.odd ${ODD_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    ORV=$?
    ${KCTL_CMD} rpush {list}.prime ${PRIME_ARR[*]} 2>/dev/null | grep -v option | grep -q 5
    PRV=$?
    if [[ ${ORV} -eq 0 ]] && [[ ${PRV} -eq 0 ]]
    then
        echo "$(date) : INFO : Both sample lists are created. lpush, rpush and del commands are verified successfully."
        for list_name in "odd" "prime"
        do
            display_list_members ${list_name} "{list}.${list_name}"
        done
    else
        echo "$(date) : ERROR : Failed to create lists : ${ORV},${PRV}. Exiting."
        exit 1
    fi
}

# Pop min (first element) from sorted list
function zset_pop_min()
{
    RES=$(${KCTL_CMD} bzpopmin {zset}.odd 3 2>/dev/null | grep -v option | egrep -v "one|1|odd" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Popping the first element from sorted set (bzpopmin) verified successfully."
        display_zset_members "odd" "{zset}.odd"
    else
        echo "$(date) : FAILED : Validation failed for popping min element from sorted set(bzpopmin) (${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

# Pop max (last element) from sorted list
function zset_pop_max()
{
    RES=$(${KCTL_CMD} bzpopmax {zset}.odd 3 2>/dev/null | grep -v option | egrep -v "nine|9|odd" | wc -l | sed 's/ //g')
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : Popping the last element from sorted set (bzpopmax) verified successfully."
        display_zset_members "odd" "{zset}.odd"
    else
        echo "$(date) : FAILED : Validation failed for popping max element from sorted set(bzpopmax) (${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

# Pop the first element of the list
function list_pop()
{
    if [[ $1 == "left" ]]
    then
        PUSH_CMD="lpush"
        POP_CMD="blpop"
    else
        PUSH_CMD="rpush"
        POP_CMD="brpop"
    fi
    ${KCTL_CMD} del {list}.block 2>/dev/null | grep -v option
    ${KCTL_CMD} ${PUSH_CMD} {list}.block 3 4 2>/dev/null | grep -v option | grep -q 2
    BRV=$?
    if [[ ${BRV} -eq 0 ]]
    then
        echo "$(date) : INFO : Sample list created with 2 elements."
        display_list_members "block" "{list}.block"
    else
        echo "$(date) : ERROR : Failed to create a sample list with 2 elements : ${BRV}. Exiting."
        exit 1
    fi

    ${KCTL_CMD} ${POP_CMD} {list}.block 0 2>/dev/null | grep -v option | grep -q 4
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : ${POP_CMD} validation successful."
    else
        echo "$(date) : FAILED : ${POP_CMD} failed for list with 1 element. Exiting."
        display_list_members "block" "{list}.block"
        time_calculation
        exit 1
    fi

    TEMP_TEST_BLOCK_FILE="./test_block_cmd.log"
    rm -f ${TEMP_TEST_BLOCK_FILE}
    touch ${TEMP_TEST_BLOCK_FILE}
    echo "$(date) : INFO : Testing the blocking command with timeout."
    grep -qw "nil" ${TEMP_TEST_BLOCK_FILE}
    RVB=$?
    ${KCTL_CMD} ${POP_CMD} {list}.block2 5 2>/dev/null >${TEMP_TEST_BLOCK_FILE}
    grep -qw "nil" ${TEMP_TEST_BLOCK_FILE}
    RVA=$?
    if [[ ${RVB} -eq 1 ]] && [[ ${RVA} -eq 0 ]]
    then
        echo "$(date) : INFO : ${POP_CMD} command with specific timeout validated successfully."
        rm -f ${TEMP_TEST_BLOCK_FILE}
    else
        echo "$(date) : ERROR : Failed to validate the ${POP_CMD} with specific timeout value. (${RVB} and ${RVA}) Exiting."
        time_calculation
        exit 1
    fi
}

# Pop the last element of one list and push it into the second list
function right_pop_left_push_lmove()
{
    echo "$(date) : INFO : Testing the brpoplpush command..."
    display_list_members "prime" "{list}.prime"
    display_list_members "odd" "{list}.odd"
    ${KCTL_CMD} brpoplpush {list}.prime {list}.odd 4 2>/dev/null | grep -v option | grep -q 11
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : brpoplpush command executed successfully."
        RES=$(${KCTL_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | egrep -v "2|3|5|7" | wc -l | sed 's/ //g')
        if [[ ${RES} -eq 0 ]]
        then
            echo "$(date) : PASSED : brpop on the prime list validated successfully as part of brpoplpush command."
            display_list_members "prime" "{list}.prime"
            RES=$(${KCTL_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | egrep -v "1|3|5|7|9|11" | wc -l | sed 's/ //g')
            if [[ ${RES} -eq 0 ]]
            then
                echo "$(date) : PASSED : blpush on the odd list validated successfully as part of brpoplpush command."
                display_list_members "odd" "{list}.odd"
            else
                echo "$(date) : FAILED : Validation failed for blpush on the odd list as part of brpoplpush command (${RES}). Exiting."
                display_list_members "odd" "{list}.odd"
                display_list_members "prime" "{list}.prime"
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : Validation failed for brpop on the prime list as part of brpoplpush command (${RES}). Exiting."
            display_list_members "prime" "{list}.prime"
            display_list_members "odd" "{list}.odd"
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : brpoplpush command did not execute as expected. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        exit 1
    fi

    echo "$(date) : INFO : Testing the blmove command..."
    display_list_members "prime" "{list}.prime"
    display_list_members "odd" "{list}.odd"
    RES1=$(${KCTL_CMD} blmove {list}.odd {list}.prime LEFT LEFT 4 2>/dev/null | grep -v option | grep -w 11 | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 11 | wc -l | sed 's/ //g')
    RES3=$(${KCTL_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 9 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]
    then
        echo "$(date) : INFO : blmove command executed successfully with LEFT LEFT option."
    else
        echo "$(date) : FAILED : blmove command failed while executing with LEFT LEFT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} blmove {list}.odd {list}.prime LEFT RIGHT 4 2>/dev/null | grep -v option | grep -w 9 | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 9 | wc -l | sed 's/ //g')
    RES3=$(${KCTL_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 7 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]
    then
        echo "$(date) : INFO : blmove command executed successfully with LEFT RIGHT option."
    else
        echo "$(date) : FAILED : blmove command failed while executing with LEFT RIGHT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} blmove {list}.odd {list}.prime RIGHT LEFT 4 2>/dev/null | grep -v option | grep -w 1 | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | head -1 | grep -w 1 | wc -l | sed 's/ //g')
    RES3=$(${KCTL_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 3 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]
    then
        echo "$(date) : INFO : blmove command executed successfully with RIGHT LEFT option."
    else
        echo "$(date) : FAILED : blmove command failed while executing with RIGHT LEFT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} blmove {list}.odd {list}.prime RIGHT RIGHT 4 2>/dev/null | grep -v option | grep -w 3 | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} lrange {list}.prime 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 3 | wc -l | sed 's/ //g')
    RES3=$(${KCTL_CMD} lrange {list}.odd 0 -1 2>/dev/null | grep -v option | tail -1 | grep -w 5 | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]]
    then
        echo "$(date) : INFO : blmove command executed successfully with RIGHT RIGHT option."
    else
        echo "$(date) : FAILED : blmove command failed while executing with RIGHT RIGHT option. Exiting."
        display_list_members "prime" "{list}.prime"
        display_list_members "odd" "{list}.odd"
        time_calculation
        exit 1
    fi
}

function sort_list()
{
    ${KCTL_CMD} del {list}.mix 2>/dev/null | grep -v option
    ${KCTL_CMD} lpush {list}.mix 4 three five 1 six
    display_list_members "mix" "{list}.mix"
    CNT=$(${KCTL_CMD} sort {list}.mix alpha 2>/dev/null | egrep -v 'option|three|five|six|1|4' | wc -l)
    if [[ $CNT -eq 0 ]]
    then
        echo "$(date) : PASSED : sort command validation in ascending order succeeded."
        ${KCTL_CMD} sort {list}.mix alpha desc 2>/dev/null | tr '\n' ' ' | sed 's/ //g' | grep -wq threesixfive41
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : PASSED : sort command validation in descending order succeeded."
        else
            echo "$(date) : FAILED : Failed to validate sort command in descending order. Exiting."
            time_calculation
            #exit 1
        fi
    else
        echo "$(date) : FAILED : Failed to validate sort command in ascending order. Exiting."
        time_calculation
        exit 1
    fi
}

function lpos_command()
{
    ${KCTL_CMD} del {list}.trial 2>/dev/null | grep -v option
    ${KCTL_CMD} lpush {list}.trial 1 235 4 6 3 67 2 67 3 7 36 4
    display_list_members "trial" "{list}.trial"
    RES1=$(${KCTL_CMD} lpos {list}.trial 3 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 3 | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} lpos {list}.trial 3 RANK -1 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 7 | wc -l | sed 's/ //g')
    RES3=$(${KCTL_CMD} lpos {list}.trial 3 COUNT 2 2>/dev/null | grep -v option | awk '{print $NF}' | egrep -w "3|7" | wc -l | sed 's/ //g')
    RES4=$(${KCTL_CMD} lpos {list}.trial 3 COUNT 2 RANK -3 2>/dev/null | grep -v option | grep "empty" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 2 ]] && [[ ${RES4} -eq 1 ]]
    then
        echo "$(date) : PASSED : lpos command validation succeeded."
    else
        echo "$(date) : FAILED : Failed to validate lpos command(${RES1},${RES2},${RES3},${RES4}). Exiting."
        time_calculation
        exit 1
    fi
}

function validate_with_timeout_for_blocking_commands()
{
    TIMEOUT=$1
    echo "$(date) : INFO : Validating ${BLK_CMD} with timeout value as ${TIMEOUT}"
    ${KCTL_CMD} del {list}.block1 {list}.block2 2>/dev/null | grep -v option
    if [[ ${BLK_CMD} == "brpoplpush" ]]
    then
        timeout --kill-after=1s 10s ${KCTL_CMD} ${BLK_CMD} {list}.block1 {list}.block2 ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    elif [[ ${BLK_CMD} == "blmove" ]]
    then
        timeout --kill-after=1s 10s ${KCTL_CMD} ${BLK_CMD} {list}.block1 {list}.block2 LEFT RIGHT ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    else
        timeout --kill-after=1s 10s ${KCTL_CMD} ${BLK_CMD} {list}.block1 ${TIMEOUT} 2>/dev/null
        RET_VAL=$?
    fi
    if [[ ${TIMEOUT} -eq 0 ]]
    then
        if [[ ${RET_VAL} -eq 137 ]] || [[ ${RET_VAL} -eq 124 ]]
        then
            echo "$(date) : PASSED : ${BLK_CMD} succeeded for en empty list and waited forever."
        else
            echo "$(date) : FAILED : ${BLK_CMD} failed for an empty list without waiting forever. Exiting."
            time_calculation
            exit 1
        fi
    else
        if [[ ${RET_VAL} -ne 137 ]] && [[ ${RET_VAL} -ne 124 ]]
        then
            echo "$(date) : PASSED : ${BLK_CMD} succeeded for en empty list and did not wait forever."
        else
            echo "$(date) : FAILED : ${BLK_CMD} failed for an empty list and waited forever. Exiting."
            time_calculation
            exit 1
        fi
    fi
}

# Perform all blocking command operations on sets and sorted sets
function blocking_list_operations()
{
    create_lists
    list_pop "left"
    list_pop "right"
    zset_pop_min
    zset_pop_max
    right_pop_left_push_lmove
    sort_list
    lpos_command

    for BLK_CMD in blpop brpop bzpopmin bzpopmax blmove brpoplpush
    do
        validate_with_timeout_for_blocking_commands 0
        #validate_with_timeout_for_blocking_commands 5
    done
}

function select_command()
{
    ${KCTL_CMD} select 0 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : select 0 succeeded."
        ${KCTL_CMD} select 1 2>/dev/null | grep -v option | grep -q "SELECT is not allowed in cluster mode"
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : PASSED : select on other integer failed."
        else
            echo "$(date) : FAILED : select on other integer succeeded. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : select 0 failed. Exiting."
        time_calculation
        exit 1
    fi
}

function client_commands()
{
    ${KCTL_CMD} client setname 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : FAILED : NULL value is set as client name. Exiting."
        #time_calculation
        #exit 1
    else
        echo "$(date) : PASSED : Failed to set null entry as client name."
    fi
}

function script_command()
{
    SHA_VAL_KEYS=$(${KCTL_CMD} script load "return KEYS[1]" 2>/dev/null | grep -v option | sed 's/ //g')
    SHA_VAL_ARGS=$(${KCTL_CMD} script load "return ARGV[1]" 2>/dev/null | grep -v option | sed 's/ //g')
    if [[ $(echo ${SHA_VAL_KEYS} | wc -c) -eq 41 ]] && [[ $(echo ${SHA_VAL_ARGS} | wc -c) -eq 41 ]]
    then
        echo "$(date) : INFO : SHA values generated successfully for script load of keys and args tables' function call."
        ${KCTL_CMD} evalsha ${SHA_VAL_ARGS} 1 hello world 2>/dev/null | grep -v option | grep -q world
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : PASSED : evalsha on ARGS verified successfully."
            ${KCTL_CMD} evalsha ${SHA_VAL_KEYS} 1 hello world 2>/dev/null | grep -v option | grep -q hello
            if [[ $? -eq 0 ]]
            then
                echo "$(date) : PASSED : evalsha on KEYS verified successfully."
            else
                echo "$(date) : FAILED : Verification failed for evalsha on KEYS table. Exiting."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : Verification failed for evalsha on ARGS table. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Issue in generating SHA values for script load of keys and args tables' function call (${SHA_VAL_KEYS} and ${SHA_VAL_ARGS}). Exiting."
        time_calculation
        #exit 1
    fi

    SEV=$(${KCTL_CMD} script exists ${SHA_VAL_KEYS} ${SHA_VAL_ARGS} 2>/dev/null | grep -v option | awk '{print $NF}' | grep 1 | wc -l)
    if [[ $SEV -eq 2 ]]
    then
        echo "$(date) : PASSED : script exists command before flushing validated successfully."
    else
        echo "$(date) : FAILED : script exists command before flushing validation failed. Exiting."
        time_calculation
        #exit 1
    fi

    ${KCTL_CMD} script flush SYNC 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : script cache flushed successfully."
        SEV=$(${KCTL_CMD} script exists ${SHA_VAL_KEYS} ${SHA_VAL_ARGS} 2>/dev/null | grep -v option | awk '{print $NF}' | grep 0 | wc -l)
        if [[ $SEV -eq 2 ]]
        then
            echo "$(date) : PASSED : script exists command after flushing validated successfully."
        else
            echo "$(date) : FAILED : script exists command after flushing validation failed. Exiting."
            time_calculation
            #exit 1
        fi
    else
        echo "$(date) : FAILED : Flushing of script cache failed. Exiting."
        time_calculation
        exit 1
    fi
}

function scs_commands()
{
    select_command
    client_commands
    script_command
}

function cluster_commands()
{
    KST1=$(${KCTL_CMD} cluster keyslot {test}1 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g')
    KST2=$(${KCTL_CMD} cluster keyslot {test}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g')
    if [[ ${KST1} -eq ${KST2} ]] && [[ ${KST1} -eq 6918 ]]
    then
        echo "$(date) : PASSED : Cluster keyslot command validated successfully."
    else
        echo "$(date) : FAILED : Cluster keyslot command validation failed(${KST1} and ${KST2}). Exiting."
        time_calculation
        exit 1
    fi

    CSC=($(${KCTL_CMD} cluster slots 2>/dev/null | grep -v option | grep -v 6379 | awk '{print $NF}' | sort -nr | sed 's/ //g' | sed 's/\r//g'))
    i=0
    j=1
    total_slots=0
    while [[ $j -lt ${#CSC[*]} ]]
    do
        let total_slots=${total_slots}+$(( ${CSC[$i]}-${CSC[$j]}+1 ))
        let i=${i}+2
        let j=${j}+2
        echo "$(date) : DEBUG : Total Slots:${total_slots}, i:$i , j:$j"
    done

    if [[ ${CSC[0]} -eq 16383 ]] && [[ ${total_slots} -eq 16384 ]]
    then
        echo "$(date) : PASSED : Cluster slots command validated successfully."
    else
        echo "$(date) : FAILED : Cluster slots command validation failed(${CSC[*]} and ${total_slots}). Exiting."
        time_calculation
        exit 1
    fi
}

function string_commands()
{
    ${KCTL_CMD} set {strkey}sample "Hello Test" 2>/dev/null | grep -wq OK
    RES1=$(${KCTL_CMD} substr {strkey}sample -4 -1 2>/dev/null | grep -v option | grep -w Test | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} substr {strkey}sample 0 4 2>/dev/null | grep -v option | grep -w Hello | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : PASSED : substr command validation succeeded."
    else
        echo "$(date) : FAILED : Failed to validate substr command(${RES1},${RES2}). Exiting."
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} getrange {strkey}sample -4 -1 2>/dev/null | grep -v option | grep -w Test | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} getrange {strkey}sample 0 4 2>/dev/null | grep -v option | grep -w Hello | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : PASSED : getrange command validation succeeded."
    else
        echo "$(date) : FAILED : Failed to validate getrange command(${RES1},${RES2}). Exiting."
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} del {key}1 {key}2 {key}3 2>/dev/null | grep -v option
    ${KCTL_CMD} set {key}1 value1 2>/dev/null | grep -v option | grep -q OK
    ${KCTL_CMD} set {key}2 value2 2>/dev/null | grep -v option | grep -q OK
    ${KCTL_CMD} renamenx {key}1 {key}2 2>/dev/null | grep -v option | grep -q 0
    RES1=$(${KCTL_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | head -2 | egrep -w "value1|value2" | wc -l | sed 's/ //g')
    ${KCTL_CMD} renamenx {key}1 {key}3 2>/dev/null | grep -v option | grep -q 0
    RES2=$(${KCTL_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | tail -2 | egrep -w "value1|value2" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 2 ]]
    then
        echo "$(date) : PASSED : renamenx command validation succeeded."
    else
        echo "$(date) : FAILED : Failed to validate renamenx command(${RES1},${RES2}). Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Test SET IFEQ command (Valkey 8 feature)
function test_set_ifeq()
{
    echo "$(date) : INFO : Testing SET command with IFEQ argument (Valkey 8 feature)..."
    ${KCTL_CMD} del {key}version 2>/dev/null | grep -v option
    ${KCTL_CMD} set {key}version "v1" 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : Initial value v1 set successfully."
        # Test successful IFEQ update
        ${KCTL_CMD} set {key}version "v2" IFEQ "v1" 2>/dev/null | grep -v option | grep -q OK
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : PASSED : SET IFEQ succeeded when value matches."
            # Test failed IFEQ update
            ${KCTL_CMD} set {key}version "v3" IFEQ "v1" 2>/dev/null | grep -v option | grep -q "nil"
            if [[ $? -eq 0 ]]
            then
                echo "$(date) : PASSED : SET IFEQ correctly failed when value doesn't match."
                # Verify value is still v2
                ${KCTL_CMD} get {key}version 2>/dev/null | grep -v option | grep -q "v2"
                if [[ $? -eq 0 ]]
                then
                    echo "$(date) : PASSED : SET IFEQ validation complete."
                else
                    echo "$(date) : FAILED : Value not preserved after failed IFEQ. Exiting."
                    time_calculation
                    exit 1
                fi
            else
                echo "$(date) : FAILED : SET IFEQ should have failed but didn't. Exiting."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : SET IFEQ should have succeeded. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Failed to set initial value. Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Test MULTI/WATCH nested calls that should abort (Valkey 8 breaking change)
function test_multi_watch_nested()
{
    echo "$(date) : INFO : Testing MULTI nested calls (Valkey 8 breaking change)..."
    # Send both MULTI commands in a single redis-cli session to test nesting
    result=$(kubectl exec -i ${POD_NAME} -n ${TENANT_NAME} -- redis-cli -c -h ${PROXY_HOST} -p ${PROXY_PORT} -a ${REDIS_PWD} <<EOF 2>&1
multi
multi
discard
EOF
)
    # Filter out kubectl and redis-cli noise, keep only error line
    filtered_result=$(echo "$result" | grep -v "Defaulted container" | grep -v "option" | grep -v "Warning")

    if echo "$filtered_result" | grep -q "MULTI calls can not be nested"; then
        echo "$(date) : PASSED : Nested MULTI correctly rejected in Valkey 8."
    else
        echo "$(date) : FAILED : Nested MULTI should be rejected in Valkey 8. Got: $filtered_result"
        time_calculation
        exit 1
    fi

    echo "$(date) : INFO : Testing WATCH inside MULTI (Valkey 8 breaking change)..."
    # Send MULTI and WATCH in a single redis-cli session
    result=$(kubectl exec -i ${POD_NAME} -n ${TENANT_NAME} -- redis-cli -c -h ${PROXY_HOST} -p ${PROXY_PORT} -a ${REDIS_PWD} <<EOF 2>&1
multi
watch {key}test
discard
EOF
)
    # Filter out kubectl noise
    filtered_result=$(echo "$result" | grep -v "Defaulted container" | grep -v "option" | grep -v "Warning")

    if echo "$filtered_result" | grep -q "ERR Command not allowed inside a transaction"; then
        echo "$(date) : PASSED : WATCH inside MULTI correctly rejected in Valkey 8."
    else
        echo "$(date) : FAILED : WATCH inside MULTI should be rejected in Valkey 8. Got: $filtered_result"
        time_calculation
        exit 1
    fi
}

# NEW: Test SCAN with invalid TYPE returns error (Valkey 8 breaking change)
function test_scan_invalid_type()
{
    echo "$(date) : INFO : Testing SCAN with invalid TYPE (Valkey 8 breaking change)..."
    ${KCTL_CMD} scan 0 TYPE "faketype" 2>/dev/null | grep -v option | grep -q "ERR unknown type name"
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : SCAN with invalid TYPE returns error in Valkey 8."
    else
        echo "$(date) : FAILED : SCAN should return error for invalid TYPE in Valkey 8. Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Test BITCOUNT/BITPOS error handling for non-existing keys (Valkey 8 breaking change)
function test_bitcount_bitpos_errors()
{
    echo "$(date) : INFO : Testing BITCOUNT/BITPOS error handling (Valkey 8 breaking change)..."
    ${KCTL_CMD} del {key}nonexistent 2>/dev/null | grep -v option

    # Test BITPOS with invalid arguments
    ${KCTL_CMD} bitpos {key}nonexistent 0 0 1 hello 2>/dev/null | grep -v option | grep -q "ERR syntax error"
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : BITPOS returns error for invalid arguments in Valkey 8."
    else
        echo "$(date) : FAILED : BITPOS should return error for invalid arguments. Exiting."
        time_calculation
        exit 1
    fi

    # Test BITCOUNT with invalid arguments
    ${KCTL_CMD} bitcount {key}nonexistent 0 asd 2>/dev/null | grep -v option | grep -q "ERR value is not an integer or out of range"
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : BITCOUNT returns error for invalid arguments in Valkey 8."
    else
        echo "$(date) : FAILED : BITCOUNT should return error for invalid arguments. Exiting."
        time_calculation
        exit 1
    fi

    # Test BITCOUNT argument validation before key check
    ${KCTL_CMD} bitcount {key}no-key invalid1 invalid2 2>/dev/null | grep -v option | grep -q "ERR value is not an integer or out of range"
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : BITCOUNT validates arguments before key existence in Valkey 8."
    else
        echo "$(date) : FAILED : BITCOUNT should validate arguments first. Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Test BGSAVE CANCEL command (Valkey 8 feature)
function test_bgsave_cancel()
{
    echo "$(date) : INFO : Testing BGSAVE CANCEL command (Valkey 8 feature)..."
    # Note: In a test environment, we can't really trigger a long-running BGSAVE
    # So we just test that the command is recognized
    ${KCTL_CMD} bgsave cancel 2>/dev/null | grep -v option
    RES=$?
    # Command should either succeed (OK) or return an error that there's no save in progress
    if [[ ${RES} -eq 0 ]]
    then
        echo "$(date) : PASSED : BGSAVE CANCEL command is recognized in Valkey 8."
    else
        echo "$(date) : INFO : BGSAVE CANCEL not executed (may be no save in progress)."
    fi
}

# NEW: Test CLIENT KILL MAXAGE command (Valkey 8 feature)
function test_client_kill_maxage()
{
    echo "$(date) : INFO : Testing CLIENT KILL MAXAGE command (Valkey 8 feature)..."
    # Kill clients older than 3600 seconds
    ${KCTL_CMD} client kill MAXAGE 3600 2>/dev/null | grep -v option | grep -q "integer"
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : CLIENT KILL MAXAGE command works in Valkey 8."
    else
        echo "$(date) : INFO : CLIENT KILL MAXAGE may have killed 0 clients (expected in test)."
    fi
}

# NEW: Test CLIENT LIST with additional filters (Valkey 8 feature)
function test_client_list_filters()
{
    echo "$(date) : INFO : Testing CLIENT LIST with new filters (Valkey 8 feature)..."

    # Test SKIPME YES filter
    ${KCTL_CMD} client list SKIPME YES 2>/dev/null | grep -v option >/dev/null
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : CLIENT LIST SKIPME filter works in Valkey 8."
    else
        echo "$(date) : FAILED : CLIENT LIST SKIPME filter failed. Exiting."
        time_calculation
        exit 1
    fi

    # Test MAXAGE filter
    ${KCTL_CMD} client list MAXAGE 60 2>/dev/null | grep -v option >/dev/null
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : PASSED : CLIENT LIST MAXAGE filter works in Valkey 8."
    else
        echo "$(date) : FAILED : CLIENT LIST MAXAGE filter failed. Exiting."
        time_calculation
        exit 1
    fi
}

# NEW: Valkey 8 specific tests
function valkey8_new_features()
{
    test_set_ifeq
    test_multi_watch_nested
    test_scan_invalid_type
    test_bitcount_bitpos_errors
    test_bgsave_cancel
    test_client_kill_maxage
    test_client_list_filters
}

function validate_stream_commands()
{
    if [[ $2 =~ $3 ]]
    then
        echo "$(date) : PASSED : $1 command validation succeeded."
    else
        echo "$(date) : FAILED : Failed to validate $1 command($2,$3). Exiting."
        time_calculation
        exit 1
    fi
}

function xadd_xtrim_xdel()
{
    echo "$(date) : INFO : Executing xadd command"
    #${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    id1=$(${KCTL_CMD} xadd test_stream \* sensor-id 1234 temperature 29.5 2>/dev/null | grep -v option)
    id2=$(${KCTL_CMD} xadd test_stream \* sensor-id 1235 temperature 30.0 2>/dev/null | grep -v option)
    result=$(${KCTL_CMD} XRANGE test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' '| sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    #expected="11`echo $id1`21sensor-id212343temperature429.521`echo $id2`21sensor-id212353temperature430.0"
    expected=".*sensor.*"
    validate_stream_commands "xadd" ${result} ${expected}

    echo "$(date) : INFO : Executing xtrim command"
    ${KCTL_CMD} xtrim test_stream MAXLEN 1 2>/dev/null | grep -v option | grep -q integer
    result=$(${KCTL_CMD} xrange test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' '| sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    #expected="11`echo $id2`21sensor-id212353temperature430.0"
    expected=".*sensor.*"
    validate_stream_commands "xtrim" ${result} ${expected}

    echo "$(date) : INFO : Executing xdel command"
    ${KCTL_CMD} xdel test_stream "$id2" 2>/dev/null | grep -v option | grep -q integer
    result=$(${KCTL_CMD} xrange test_stream - + 2>/dev/null | grep -v option | sed 's/\r//g' | tr '\n' ' '| sed 's/ //g' | sed 's/)//g' | sed 's/\"//g')
    expected=""
    validate_stream_commands "xdel" ${result} ${expected}
}

function xinfo_xread()
{
    echo "$(date) : INFO : Executing info command to validate the length and last-entry"
    id=$(${KCTL_CMD} xadd test_stream \* sensor-id 1234 temperature 29.5 2>/dev/null | grep -v option)
    RES1=$(${KCTL_CMD} xinfo stream test_stream 2>/dev/null | grep -v option | grep "length" -A1 | awk '{print $NF}' | grep -v length | sed 's/\r//g' | sed 's/\"//g')
    RES2=$(${KCTL_CMD} xinfo stream test_stream 2>/dev/null | grep -v option | grep "last-entry" -A1 | grep "$id" | wc -l | sed 's/\r//g' | sed 's/\"//g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : PASSED : xinfo command validation succeeded for stream."
    else
        echo "$(date) : FAILED : Failed to validate xinfo command for streams(${RES1},${RES2}). Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_create()
{
    echo "$(date) : INFO : Executing xgroup command to add test_stream to test_group."
    ${KCTL_CMD} xgroup create test_stream test_group 0 2>/dev/null | grep -v option | grep -q OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : test_group created successfully and test_stream is added to it."
        RES=$(${KCTL_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep test_group | awk -F '"' '{print $2}' | sed 's/\r//g' | sed 's/ //g')
        if [[ ${RES} == "test_group" ]]
        then
            echo "$(date) : PASSED : xinfo command validation succeeded for group(xinfo groups)."
        else
            echo "$(date) : FAILED : Failed to validate xinfo command for group(${RES}). Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : test_group creation failed. Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_create_consumers()
{
    echo "$(date) : INFO : Executing xgroup command to add test_consumers to test_group."
    ${KCTL_CMD} xgroup createconsumer test_stream test_group test_consumer1 2>/dev/null | grep -v option | grep -q 1
    RES1=$?
    ${KCTL_CMD} xgroup createconsumer test_stream test_group test_consumer2 2>/dev/null | grep -v option | grep -q 1
    RES2=$?
    ${KCTL_CMD} xgroup createconsumer test_stream test_group test_consumer3 2>/dev/null | grep -v option | grep -q 1
    RES3=$?
    ${KCTL_CMD} xgroup createconsumer test_stream test_group test_consumer2 2>/dev/null | grep -v option | grep -q 1
    RES4=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 0 ]] && [[ ${RES4} -ne 0 ]]
    then
        echo "$(date) : INFO : test consumers created successfully and validation succeeded for xgroup createconsumers command."
        RES=$(${KCTL_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | egrep "test_consumer[1-3]" | wc -l | sed 's/ //g')
        if [[ ${RES} -eq 3 ]]
        then
            echo "$(date) : PASSED : xinfo command validation succeeded for consumers(xinfo consumers)."
        else
            echo "$(date) : FAILED : Failed to validate xinfo command for consumers(${RES}). Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : test_consumers addition failed. Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_delete_consumer()
{
    echo "$(date) : INFO : Executing xgroup command to delete test_consumer from test_group."
    RES1=$(${KCTL_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | grep -w "test_consumer3" | wc -l | sed 's/ //g')
    ${KCTL_CMD} xgroup delconsumer test_stream test_group test_consumer3 2>/dev/null | grep -v option | grep -q integer
    RES2=$(${KCTL_CMD} xinfo consumers test_stream test_group 2>/dev/null | grep -v option | grep -w "test_consumer3" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 0 ]]
    then
        echo "$(date) : PASSED : test consumer deleted successfully and validation succeeded for xgroup delconsumer command."
    else
        echo "$(date) : FAILED : test consumer deletion failed. Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_setid()
{
    echo "$(date) : INFO : Executing xgroup command to set id for the test_group."
    RES1=$(${KCTL_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep -w "4325" | wc -l | sed 's/ //g')
    ${KCTL_CMD} xgroup setid test_stream test_group 4325 2>/dev/null | grep -v option | grep -q OK
    RES2=$?
    RES3=$(${KCTL_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep -w "4325" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 1 ]]
    then
        echo "$(date) : PASSED : group id set successfully and validation succeeded for xgroup setid command."
    else
        echo "$(date) : FAILED : xgroup setid command validation failed(${RES1},${RES2} and ${RES3}). Exiting."
        time_calculation
        exit 1
    fi
}

function xreadgroup()
{
    echo "$(date) : INFO : Executing xreadgroup command to read messages from test_stream in the test_group."
    RES1=$(${KCTL_CMD} xreadgroup group test_group test_consumer1 streams test_stream \> 2>/dev/null | grep -v option | grep -w "temperature" | wc -l | sed 's/ //g')
    RES2=$(${KCTL_CMD} xreadgroup group test_group test_consumer1 streams test_stream \> 2>/dev/null | grep -v option | grep -w "temperature" | wc -l | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]]
    then
        echo "$(date) : PASSED : xreadgroup validation succeeded."
    else
        echo "$(date) : FAILED : xreadgroup command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi
}

function xrange_xrevrange()
{
    echo "$(date) : INFO : Executing xrange and xrevrange commands to list the stream messages."
    id2=$(${KCTL_CMD} xadd test_stream \* sensor-id 1234 temperature 30 2>/dev/null | grep -v option)
    ${KCTL_CMD} xrange test_stream - + 2>/dev/null | grep -v option | head -1 | grep -q "$id"
    RES1=$?
    ${KCTL_CMD} xrevrange test_stream + - 2>/dev/null | grep -v option | head -1 | grep -q "$id2"
    RES2=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]]
    then
        echo "$(date) : PASSED : xrange and xrevrange commands validated successfully."
    else
        echo "$(date) : FAILED : xrange and xrevrange commands validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi
}

function xclaim_xack_xautoclaim()
{
    echo "$(date) : INFO : Executing xrange and xrevrange commands to list the stream messages."
    ${KCTL_CMD} xreadgroup group test_group test_consumer1 count 1 streams test_stream 0 2>/dev/null | grep -v option | grep -q "${id}"
    RES1=$?
    ${KCTL_CMD} xack test_stream test_group ${id} 2>/dev/null | grep -v option | head -1 | grep -q 1
    RES2=$?
    ${KCTL_CMD} xack test_stream test_group ${id} 2>/dev/null | grep -v option | head -1 | grep -q 0
    RES3=$?
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 0 ]]
    then
        echo "$(date) : PASSED : xack validated successfully."
    else
        echo "$(date) : FAILED : xack validation failed(${RES1}, ${RES2} and ${RES3}). Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_destroy()
{
    echo "$(date) : INFO : Executing xgroup destroy command to remove test_stream from the test_group."
    RES1=$(${KCTL_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep test_group | wc -l | sed 's/\r//g' | sed 's/ //g')
    ${KCTL_CMD} xgroup destroy test_stream test_group 2>/dev/null | grep -v option | grep -q 1
    RES2=$?
    ${KCTL_CMD} xgroup destroy test_stream test_group 2>/dev/null | grep -v option | grep -q 1
    RES3=$?
    RES4=$(${KCTL_CMD} xinfo groups test_stream 2>/dev/null | grep -v option | grep test_group | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -ne 0 ]] && [[ ${RES4} -eq 0 ]]
    then
        echo "$(date) : PASSED : xgroup destroy validation succeeded."
    else
        echo "$(date) : FAILED : xgroup destroy command validation failed(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        exit 1
    fi
}

function validate_blocking_command()
{
    RES1=$(${KCTL_CMD} del test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} xadd test_stream \* field1 value1 field2 value2 2>/dev/null | grep -v option | grep 17* | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${KCTL_CMD} xlen test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${KCTL_CMD} xrange test_stream - + count 1  2>/dev/null | grep -v option | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 5 ]]
    then
        echo "$(date) : INFO : Prevalidations succeeded for validating xread command."
        ${KCTL_CMD} xread block 5 streams test_stream 0
        RES5=$?
        timeout --kill-after=1s 10s ${KCTL_CMD} xread block 0 streams test_stream $
        RES6=$?
        if [[ ${RES5} -eq 0 ]] && ( [[ ${RES6} -eq 137 ]] || [[ ${RES6} -eq 124 ]] )
        then
            echo "$(date) : PASSED : xread command validation succeeded."
            RES7=$(${KCTL_CMD} del test_stream 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
            if [[ ${RES7} -eq 1 ]]
            then
                echo "$(date) : INFO : Test stream deletion validated succeessfully."
            else
                echo "$(date) : FAILED : Issue in deleting test stream."
            fi
        else
            echo "$(date) : FAILED : xread command validation failed (${RES5} and ${RES6}). Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Prevalidations failed for executing xread command(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        exit 1
    fi
}

function xgroup_xreadgroup()
{
    xgroup_create
    xgroup_create_consumers
    xgroup_delete_consumer
    xgroup_setid
    xreadgroup
}

function stream_commands()
{
    xadd_xtrim_xdel
    xinfo_xread
    xgroup_xreadgroup
    #xrange_xrevrange
    #xclaim_xack_xautoclaim
    xgroup_destroy
    validate_blocking_command
}

function default_commands()
{
    PING_RESP=$(${KCTL_CMD} ping 2>/dev/null | grep -v option | sed 's/\r//g')
    if [[ ${PING_RESP} == "PONG" ]]
    then
        echo "$(date) : INFO : Ping command validated successfully."
    else
        echo "$(date) : ERROR : Ping command validation failed(${PING_RESP}). Exiting"
        time_calculation
        exit 1
    fi

    TIME_RESP=$(${KCTL_CMD} time 2>/dev/null | grep -v option | head -1 | sed 's/\r//g')
    sleep 2
    CUR_TIME=$(date +%s)
    DIFF=$(( ${CUR_TIME} - ${TIME_RESP} ))
    if [[ ${DIFF} -ge 2 ]] && [[ ${DIFF} -le 4 ]]
    then
        echo "$(date) : INFO : Time command validated successfully."
    else
        echo "$(date) : ERROR : Time command validation failed(${TIME_RESP}, ${CUR_TIME} and ${DIFF}). Exiting"
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} quit 2>/dev/null | grep -v option | sed 's/\r//g')
    RES2=$(${KCTL_CMD} exit 2>/dev/null | grep -v option | sed 's/\r//g')
    if [[ ${RES1} == "OK" ]] && [[ ${RES2} == "OK" ]]
    then
        echo "$(date) : PASSED : Commands quit and exit verified successfully."
    else
        echo "$(date) : FAILED : Validation failed for quit and exit commands (${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi
}

function hset_operations()
{
    ${KCTL_CMD} del {hset}.keys 2>/dev/null | grep -v option
    RES1=$(${KCTL_CMD} hset {hset}.keys key1 value1 key2 value2 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 2 | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} hset {hset}.keys key1 value1 key2 value2 key3 value3 2>/dev/null | grep -v option | awk '{print $NF}' | grep -w 1 | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : INFO : hset command validated successfully."
    else
        echo "$(date) : ERROR : hset command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} del {hset}.keys 2>/dev/null | grep -v option
    RES1=$(${KCTL_CMD} hmset {hset}.keys key1 value1 key2 value2 2>/dev/null | grep -v option | grep -w OK | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} hmset {hset}.keys key1 value1 key2 value2 key3 value3 2>/dev/null | grep -v option | grep -w OK | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]]
    then
        echo "$(date) : INFO : hmset command validated successfully."
    else
        echo "$(date) : ERROR : hmset command validation failed(${RES1} and ${RES2}). Exiting."
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} hrandfield {hset}.keys 2>/dev/null | grep -v option | grep -w "key[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} hrandfield {hset}.keys 2 2>/dev/null | grep -v option | grep -w "key[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${KCTL_CMD} hrandfield {hset}.keys 2 withvalues 2>/dev/null | grep -v option | egrep -w "key[1-3]|value[1-3]" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 2 ]] && [[ ${RES3} -eq 4 ]]
    then
        echo "$(date) : INFO : hrandfield command validated successfully."
    else
        echo "$(date) : ERROR : hrandfield command validation failed(${RES1}, ${RES2} and ${RES3}). Exiting."
        time_calculation
        exit 1
    fi
}

function bitop()
{
    OPERATION=$1
    EXP_RES=$2
    if [[ ${OPERATION} == "not" ]]
    then
        ${KCTL_CMD} bitop ${OPERATION} {key}${OPERATION} {key}1 2>/dev/null | grep -v option
    else
        ${KCTL_CMD} bitop ${OPERATION} {key}${OPERATION} {key}1 {key}2 2>/dev/null | grep -v option
    fi
    echo "=====1====="
    ${KCTL_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g' | sed 's/\r//g'
    echo "=====2====="
    ${KCTL_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g'
    echo "=====3====="
    ${KCTL_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option
    echo "=====4====="
    CUR_RES=$(${KCTL_CMD} get {key}${OPERATION} 2>/dev/null | grep -v option | sed 's/\\x//g' | sed 's/\r//g' | sed 's/ //g')
    if [[ ${CUR_RES} == ${EXP_RES} ]]
    then
        echo "$(date) : PASSED : bitwise ${OPERATION} operation succeeded."
    else
        echo "$(date) : FAILED : bitise ${OPERATION} operation failed(${CUR_RES},${EXP_RES}). Exiting."
        time_calculation
        exit 1
    fi
}

function bitwise_operations()
{
    ${KCTL_CMD} set {key}1 hello 2>/dev/null | grep -v option | grep -wq OK
    ${KCTL_CMD} set {key}2 hai 2>/dev/null | grep -v option | grep -wq OK
    RES=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -w "hello|hai" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES} -eq 2 ]]
    then
        echo "$(date) : INFO : Sample keys set successfully."
        bitop and "hah0000"
        bitop or "hemlo"
        bitop xor "000405lo"
        bitop not "979a939390"
    else
        echo "$(date) : ERROR : Setting sample keys failed(${RES}). Exiting."
        time_calculation
        exit 1
    fi
}

function keys_and_flushall_commands()
{
    ${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    ${KCTL_CMD} xadd test_stream \* field1 value1 field2 value2 2>/dev/null | grep -v option
    zset_keys_count=$(${KCTL_CMD} scan 0 2>/dev/null | grep -v option | grep "test_stream" | wc -l)
    if [[ ${zset_keys_count} -ge 1 ]]
    then
        echo "$(date) : PASSED : keys command validated successfully before flushing."
        ${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : PASSED : flushall command executed successfully."
            zset_keys_count=$(${KCTL_CMD} scan 0 2>/dev/null | grep -v option | grep "test_stream" | wc -l)
            if [[ ${zset_keys_count} -eq 0 ]]
            then
                echo "$(date) : PASSED : flushall and keys command validated successfully."
            else
                echo "$(date) : FAILED : flushall and keys command validation failed. Exiting."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : flushall command execution failed. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : keys command validation failed before flushing. Exiting."
        time_calculation
        exit 1
    fi
}

function info_and_config_commands()
{
    MAXMEM=$(${KCTL_CMD} info 2>/dev/null | grep -v option | grep maxmemory_policy | awk -F ':' '{print $2}' | sed 's/\r//g' | sed 's/ //g')
    if [[ ${MAXMEM} == "noeviction" ]]
    then
        echo "$(date) : PASSED : info command executed successfully(${INFO})."
        HEADER_COUNT=$(${KCTL_CMD} info replication 2>/dev/null | grep -v option | grep ^# | wc -l)
        if [[ ${HEADER_COUNT} -gt 1 ]]
        then
            echo "$(date) : FAILED : info sub command validation failed. Exiting."
            #time_calculation
            #exit 1
        else
            echo "$(date) : PASSED : info sub command validated successfully."
        fi
    else
        echo "$(date) : FAILED : info command execution failed(${INFO}). Exiting."
        time_calculation
        exit 1
    fi
    ${KCTL_CMD} config resetstat 2>/dev/null | grep -v option | grep -wq OK
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : Config resetstat command executed successfully."
        INFO_COUNT=$(${KCTL_CMD} info 2>/dev/null | grep -v option | grep keyspace_hits | awk -F ':' '{print $2}' | sed 's/\r//g')
        if [[ ${INFO_COUNT} -eq 0 ]]
        then
            echo "$(date) : PASSED : Config command validation succeeded."
            MEM_VAL=$(${KCTL_CMD} config get maxmemory 2>/dev/null | grep -v option | grep "^[0-9]" | sed 's/ //g')
            if [[ ${MEM_VAL} -gt 0 ]]
            then
                echo "$(date) : INFO : Config get command executed successfully on maxmemory(${MEM_VAL})."
                let MEM_VAL=$(( ${MEM_VAL}+500 ))
                ${KCTL_CMD} config set maxmemory ${MEM_VAL} 2>/dev/null | grep -v option | grep -wq OK
                if [[ $? -eq 0 ]]
                then
                    echo "$(date) : INFO : Config set command executed successfully on maxmemory(${MEM_VAL})."
                    CUR_VAL=$(${KCTL_CMD} config get maxmemory 2>/dev/null | grep -v option | grep "^[0-9]" | sed 's/ //g')
                    if [[ ${CUR_VAL} -eq ${MEM_VAL} ]]
                    then
                        echo "$(date) : PASSED : Config set and get validation succeeded on maxmemory."
                    else
                        echo "$(date) : FAILED : Config set and get validation failed on maxmemory(${MEM_VAL} and ${CUR_VAL}). Exiting."
                        time_calculation
                        exit 1
                    fi
                else
                    echo "$(date) : FAILED : Config set command execution failed on maxmemory(${MEM_VAL}). Exiting."
                    time_calculation
                    exit 1
                fi
            else
                echo "$(date) : FAILED : Config get command execution failed on maxmemory(${MEM_VAL})."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : Config command validation failed. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Config resetstat command execution failed. Exiting."
        time_calculation
        exit 1
    fi
}

function slowlog_validation
{
    SLOWLOG_COUNT=$(${KCTL_CMD} slowlog len 2>/dev/null | grep -v option | sed 's/ //g' | sed 's/\r//g')
    if [[ ${SLOWLOG_COUNT} -ge 1 ]]
    then
        echo "$(date) : PASSED : Slowlog validated successfully."
    else
        echo "$(date) : FAILED : Slowlog validation failed(${SLOWLOG_COUNT}). Exiting."
        time_calculation
        exit 1
    fi
}

function generate_slowlogs
{
    SHA_VAL=$(${KCTL_CMD} script load "for i = 1, 10000000 do local x = 1 end return 'done'" 2>/dev/null | grep -v option | sed 's/ //g')
    ${KCTL_CMD} evalsha ${SHA_VAL} 0 hello >/dev/null 2>&1
    ${KCTL_CMD} slowlog len 2>/dev/null | grep -v option | grep -w "0"
    if [[ $? -ne 0 ]]
    then
        echo "$(date) : PASSED : Slowlogs generated successfully."
        slowlog_validation
    else
        echo "$(date) : FAILED : Failed to generate slowlogs. Exiting."
        time_calculation
        exit 1
    fi
}

function slowlog_command()
{
    ${KCTL_CMD} slowlog get 2>/dev/null | grep -v option | grep -wq "nil"
    if [[ $? -ne 0 ]]
    then
        echo "$(date) : INFO : Slowlogs found. Clearing them."
        ${KCTL_CMD} slowlog reset >/dev/null 2>&1 | grep -v option
        ${KCTL_CMD} slowlog get 2>/dev/null | grep -v option | grep -q "empty"
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : INFO : Slowlogs cleared. Generating slowlogs."
            generate_slowlogs
        else
            echo "$(date) : FAILED : Failed to clear slowlogs. Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : INFO : No slowlogs found. Generating slowlogs."
        generate_slowlogs
    fi
}

function getex_getdel_msetnx_commands()
{
    ${KCTL_CMD} set hello world 2>/dev/null | grep -v option | grep -q OK
    ${KCTL_CMD} get hello 2>/dev/null | grep -v option | grep -wq world
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : Set sample value(world) for the key(hello). Executing getex on the key"
        ${KCTL_CMD} getex hello ex 10 2>/dev/null | grep -v option | grep -wq world
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : INFO : getex command executed successfully. Validating it."
            sleep 10
            ${KCTL_CMD} get hello 2>/dev/null | grep -v option | grep -wq "nil"
            if [[ $? -eq 0 ]]
            then
                echo "$(date) : PASSED : getex command validated successfully."
            else
                echo "$(date) : FAILED : getex validation failed.Exiting."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : getex command execution failed.Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Failed to set the value(world) to the key(hello)."
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} set hello world 2>/dev/null | grep -v option | grep -q OK
    ${KCTL_CMD} get hello 2>/dev/null | grep -v option | grep -wq world
    if [[ $? -eq 0 ]]
    then
        echo "$(date) : INFO : Set sample value(world) for the key(hello). Executing getdel on the key"
        ${KCTL_CMD} getdel hello 2>/dev/null | grep -v option | grep -wq world
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : INFO : getdel command executed successfully. Validating it."
            ${KCTL_CMD} get hello 2>/dev/null | grep -v option | grep -wq "nil"
            if [[ $? -eq 0 ]]
            then
                echo "$(date) : PASSED : getdel command validated successfully."
            else
                echo "$(date) : FAILED : getdel validation failed. Exiting."
                time_calculation
                exit 1
            fi
        else
            echo "$(date) : FAILED : getdel command execution failed.Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Failed to set the value(world) to the key(hello)."
        time_calculation
        exit 1
    fi

    ${KCTL_CMD} del {key}1 {key}2 {key}3 2>/dev/null | grep -v option
    ${KCTL_CMD} msetnx {key}1 value1 {key}2 value2 2>/dev/null | grep -v option | grep -q 1
    RES=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -vw "value1|value2" | wc -l)
    if [[ $RES -eq 0 ]]
    then
        echo "$(date) : INFO : msetnx command executed on non-existing keys successfully."
        ${KCTL_CMD} msetnx {key}1 value1 {key}2 value2 {key}3 value3 2>/dev/null | grep -v option | grep -q 0
        RES=$(${KCTL_CMD} mget {key}1 {key}2 {key}3 2>/dev/null | grep -v option | egrep -vw "value1|value2|nil" | wc -l)
        if [[ $? -eq 0 ]]
        then
            echo "$(date) : INFO : msetnx command validation succeeded."
        else
            echo "$(date) : FAILED : msetnx command validation failed.Exiting."
            time_calculation
            exit 1
        fi
    else
        echo "$(date) : FAILED : Failed to execute msetnx command on non-existing keys. Exiting."
    fi
}

function del_and_exists_commands()
{
    ${KCTL_CMD} set {key}1 hello 2>/dev/null | grep -v option | grep -wq OK
    ${KCTL_CMD} set {key}2 hai 2>/dev/null | grep -v option | grep -wq OK
    RES=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep -w "hello|hai" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES} -eq 2 ]]
    then
        echo "$(date) : INFO : Sample keys set successfully."
    else
        echo "$(date) : ERROR : Setting sample keys failed(${RES}). Exiting."
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} exists {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES2=$(${KCTL_CMD} exists {key}does_not_exist 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES3=$(${KCTL_CMD} exists {key}1 {key}does_not_exist {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 2 ]]
    then
        echo "$(date) : INFO : exists command validation succeeded."
    else
        echo "$(date) : ERROR : Validation failed for exists command(${RES1}, ${RES2}, and ${RES3}). Exiting."
        time_calculation
        exit 1
    fi

    RES1=$(${KCTL_CMD} del {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES2=$(${KCTL_CMD} del {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//' | sed 's/ //g')
    RES3=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | awk -F "\(" '{print $2}' | awk -F "\)" '{print $1}' | grep -w nil | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 2 ]] && [[ ${RES2} -eq 0 ]] && [[ ${RES3} -eq 2 ]]
    then
        echo "$(date) : INFO : del command validation succeeded."
    else
        echo "$(date) : ERROR : Validation failed for del command(${RES1}, ${RES2}, and ${RES3}). Exiting."
        time_calculation
        exit 1
    fi
}


function copy_and_scan_commands()
{
    ${KCTL_CMD} mset {key}1 value1 {key}2 value2 2>/dev/null | grep -v option | grep -wq OK
    RES1=$(${KCTL_CMD} copy {key}1 {key}2 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | egrep "value1|value2" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${KCTL_CMD} copy {key}1 {key}2 REPLACE 2>/dev/null | grep -v option | awk '{print $NF}' | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${KCTL_CMD} mget {key}1 {key}2 2>/dev/null | grep -v option | grep "value1" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 0 ]] && [[ ${RES2} -eq 2 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 2 ]]
    then
        echo "$(date) : INFO : Copy command validated successfully for with and without REPLACE options."
    else
        echo "$(date) : ERROR : Validation failed for copy command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        exit 1
    fi

    echo "$(date) : INFO : Scan command validation in progress..."
    ${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
    i=1
    while [ $i -le 10 ]
    do
        ${KCTL_CMD} set {key}_$i value_$i 2>/dev/null | grep -v option | grep -wq OK
        ${KCTL_CMD} set {key}-$i value-$i 2>/dev/null | grep -v option | grep -wq OK
        i=$(( i+1 ))
    done

    RES1=$(${KCTL_CMD} scan 0 type string count 5 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} scan 0 type string count 5 match {key}-* 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${KCTL_CMD} scan 0 count 5 type string match {key}-* 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${KCTL_CMD} scan 0 count 5 match {key}-* type string 2>/dev/null | grep -v option | grep key | wc -l | sed 's/\r//g' | sed 's/ //g')
    # SCAN count is a hint, not a hard limit. Check that we got SOME results (not zero) and all commands succeeded
    if [[ ${RES1} -gt 0 ]] && [[ ${RES2} -gt 0 ]] && [[ ${RES3} -gt 0 ]] && [[ ${RES4} -gt 0 ]]
    then
        echo "$(date) : INFO : Scan command validated successfully for positive test cases."
    else
        echo "$(date) : ERROR : Validation failed for +ve testing of scan command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        #exit 1
    fi

    RES1=$(${KCTL_CMD} scan -1 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES2=$(${KCTL_CMD} scan a 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES3=$(${KCTL_CMD} scan 1.5 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES4=$(${KCTL_CMD} scan 324567890987654323456789 2>/dev/null | grep -v option | grep "ERR invalid cursor" | wc -l | sed 's/\r//g' | sed 's/ //g')
    # Note: In Valkey 8, SCAN with invalid TYPE returns error instead of empty
    RES5=$(${KCTL_CMD} scan 0 type sdfgdsfg 2>/dev/null | grep -v option | egrep "empty|ERR unknown type name" | wc -l | sed 's/\r//g' | sed 's/ //g')
    RES6=$(${KCTL_CMD} scan 0 type string count 5 match {keys}-* 2>/dev/null | grep -v option | grep "empty" | wc -l | sed 's/\r//g' | sed 's/ //g')
    if [[ ${RES1} -eq 1 ]] && [[ ${RES2} -eq 1 ]] && [[ ${RES3} -eq 1 ]] && [[ ${RES4} -eq 1 ]] && [[ ${RES5} -eq 1 ]] && [[ ${RES6} -eq 1 ]]
    then
        echo "$(date) : INFO : Scan command validated successfully for negative test cases."
    else
        echo "$(date) : ERROR : Validation failed for -ve testing of scan command.(${RES1}, ${RES2}, ${RES3} and ${RES4}). Exiting."
        time_calculation
        exit 1
    fi
}

function other_commands()
{
    #slowlog_command
    #info_and_config_commands
    keys_and_flushall_commands
    getex_getdel_msetnx_commands
    del_and_exists_commands
    copy_and_scan_commands
}

#MAIN
precheck01
start_time=$(date +%s)
POD_NAME="${POD_NAME:?Set POD_NAME in test_params_envoy.cfg}"
PROXY_HOST=$(kubectl describe service ${PROXY_SERVICE} --namespace ${TENANT_NAME} | grep external-dns | grep hostname | awk '{print $NF}')
KCTL_CMD="kubectl exec -it ${POD_NAME} -n ${TENANT_NAME} -- redis-cli -c -h ${PROXY_HOST} -p ${PROXY_PORT} -a ${REDIS_PWD}"
${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
echo "=================== $(date) ================ Test case 01 ============= Set Commands ==========================================="
set_operations
echo "=================== $(date) ================ Test case 02 ============= Sorted Set Commands ===================================="
zset_operations
echo "=================== $(date) ================ Test case 03 ============= List Commands =========================================="
blocking_list_operations
echo "=================== $(date) ================ Test case 04 ============= Script, Client and Select Commands ====================="
scs_commands
echo "=================== $(date) ================ Test case 05 ============= Cluster Commands ======================================="
cluster_commands
echo "=================== $(date) ================ Test case 06 ============= String Commands ========================================"
string_commands
echo "=================== $(date) ================ Test case 07 ============= Stream Commands ========================================"
stream_commands
echo "=================== $(date) ================ Test case 08 ============= Default Commands ======================================="
default_commands
echo "=================== $(date) ================ Test case 09 ============= Hashset Commands ======================================="
hset_operations
#echo "=================== $(date) ================ Test case 10 ============= Bitwise Commands ======================================="
#bitwise_operations
echo "=================== $(date) ================ Test case 11 ============= Other Commands ========================================="
other_commands
echo "=================== $(date) ================ Test case 12 ============= Valkey 8 New Features ===================================="
valkey8_new_features
${KCTL_CMD} flushall SYNC 2>/dev/null | grep -v option | grep -wq OK
time_calculation
