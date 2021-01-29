#!/usr/bin/env bash

# THONKING
# .. ran test with contents of /tmp/emojis.txt:
cat > /tmp/emojis.txt <<EOF
<:upvote:564976298649452559> <:downvote:564976275668729858> <:codecompiles:528681838210973716> <a:upVoteParrot:705535573410054195> <a:glitchCat:662368315452424206> <:YEET:398057412453597185> <:spray:674167874784460810> <:goose_stab:675025301742288934> <:goose_pizza:675026996971175954> <:goose_alert:675026602479976488> <a:goose:675026495667699722> <a:gingerbear:557695349607890944> <:Sartre:710964717518323713> <:lacan:763458835251068958> <:FoucaultJoy:697171024936042596> <:Foucault:696749584000614472> 
<:TA_Alexander:233918483484639232> <:TA_Aristotle:233744670990008321> <:TA_Einstein:233929919728451584> <:TA_Marx:233922009401262080> <:TA_Socrates:233744714203922444> <:TA_Schopenhauer:233926863909552141> <:TA_Statue:233920379196932096> <:TA_Einstein:233929919728451584> <:TA_Plato:233744693547106304> <:TA_Crusader:233917177990873088> <:TA_Descartes:233923134649008130> <:TA_Aquinas:233924297775644673> <:TA_Machiavelli:233926372878188545> <:TA_Hegel:233925635393716224> <:TA_Nietzsche:346048719961194508>
<:freebsd:585878693646172172> <:redhat:585877192731262976> <:ubuntu:588466013339779094> <:windows:585878972353740813> <:starfleet:626913962604363824> <:adobe:652308069358895115>

<:pNani:595020147287392256>
EOF

# RUN RESULTS
# $ ./fetch_discord_emojis.sh /tmp/emojis.txt "<a:catJAM:739257396915994634> <a:uwugif:681170972291891253> <a:rave:572911134055596032> <a:dance2:640033280179175424> <a:this:786681288131608586> <a:gay:790408517827559455>" "<a:BL4_danceshark:632512616618524683>"
# 
# real	0m5.740s
# user	0m0.461s
# sys	0m0.178s
# 
# real	0m4.285s
# user	0m0.352s
# sys	0m0.146s


# For parsing pasted lines of emojis/reactions as "copy text" from mobile app (browser/OS app only copies emoji "name")
fetch_discord_emojis() { 
    for arg in "${@}"
    do
        if [[ -r "$arg" ]]
        then
            read -ra emojis < "$arg"
        else
            read -ra emojis <<<"${arg}"
        fi
        for x in "${emojis[@]}" ; do
            IFS=: read -ra arr <<<"${x}:"
            case "${arr[0]}" in
                '<') suffix=".png" ;;
                '<a') suffix=".gif" ;;
                '*') continue ;; 
            esac
            src="https://cdn.discordapp.com/emojis/${arr[2]/>/$suffix}"
            out="/tmp/${arr[1]}$suffix"
            curl -s -o "$out" "$src"
        done
    done
}

# Version two
fetch_discord_emojis_rx() { 
    for arg in "${@}"
    do 
        if [[ -r "$arg" ]]
        then
            read -ra emojis < "$arg"
        else
            emojis="$x" emojis=()
            while [[ $emojis ]]
            do
                [[ $emojis =~ ^([^:]*)(:|$) ]]
                arr+=("${BASH_REMATCH[1]}")
                emojis="${emojis#"$BASH_REMATCH"}"
            done
        fi
        for emoji in "${emojis[@]}"
        do
            pad="$x" arr=()
            while [[ $pad ]]
            do
                [[ $pad =~ ^([^:]*)(:|$) ]]
                arr+=("${BASH_REMATCH[1]}")
                pad="${pad#"$BASH_REMATCH"}"
            done
            case "${arr[0]}" in
                '<') suffix=".png" ;;
                '<a') suffix=".gif" ;;
                '*') continue ;; 
            esac
            src="https://cdn.discordapp.com/emojis/${arr[2]/>/$suffix}"
            out="/tmp/${arr[1]}$suffix"
            curl -s -o "$out" "$src"
        done
    done
}

time fetch_discord_emojis "$@"
time fetch_discord_emojis_rx "$@"
