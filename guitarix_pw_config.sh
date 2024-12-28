#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

# Fonction pour détecter les ports JACK
detect_jack_ports() {
    echo "Tentative de détection avec les ports $1 et $2..."
    OUTPUT_PORT_L=$(pw-jack jack_lsp | grep -F "$1" | head -n 1)
    OUTPUT_PORT_R=$(pw-jack jack_lsp | grep -F "$2" | head -n 1)

    if [ -n "$OUTPUT_PORT_L" ] && [ -n "$OUTPUT_PORT_R" ]; then
        echo "Ports détectés :"
        echo "Gauche : $OUTPUT_PORT_L"
        echo "Droite : $OUTPUT_PORT_R"
        return 0
    else
        echo "Ports $1 et $2 introuvables."
        return 1
    fi
}

# Fonction pour récupérer les périphériques de capture
get_capture_devices() {
    pw-jack jack_lsp | grep -E "capture" | grep -v "Midi" | sed 's/^[ \t]*//'
}

# Fonction pour déconnecter toutes les connexions existantes
disconnect_all_ports() {
    echo "Déconnexion de toutes les connexions existantes..."
    pw-jack jack_lsp | grep -E "capture|playback|output" | while read -r PORT; do
        CONNECTED_PORTS=$(pw-jack jack_lsp -c "$PORT" | awk '{print $1}' | tr -d '\r')
        for CONNECTED_PORT in $CONNECTED_PORTS; do
            pw-jack jack_disconnect "$PORT" "$CONNECTED_PORT" 2>/dev/null || true
        done
    done
    echo "Toutes les connexions précédentes ont été déconnectées."
}

# Connexion automatique pour plusieurs ports
connect_ports() {
    local src_port="$1"
    local dst_port="$2"
    if ! pw-jack jack_lsp -c "$src_port" | grep -q "$dst_port"; then
        if ! pw-jack jack_connect "$src_port" "$dst_port"; then
            zenity --error --text="Erreur lors de la connexion : $src_port -> $dst_port" --width=300
            zenity --question --text="Voulez-vous réessayer ?" --width=300
            if [ $? -eq 0 ]; then
                exec "$0"
            else
                exit 1
            fi
        else
            echo "Connexion réussie : $src_port -> $dst_port"
        fi
    else
        echo "Connexion déjà existante : $src_port -> $dst_port"
    fi
}

# Fonction pour normaliser les noms des ports (remplacement des caractères spéciaux)
normalize_port_name() {
    echo "$1" | sed 's/:/\*\*/g'
}

# Fonction pour retrouver le nom d'origine (en utilisant un tableau associatif si nécessaire)
denormalize_port_name() {
    echo "$1" | sed 's/\*\*/:/g'
}

# Détection des périphériques disponibles
capture_devices=$(get_capture_devices)
if [ -z "$capture_devices" ]; then
    zenity --error --text="Aucun périphérique de capture détecté !" --width=300
    exit 1
fi

# Convertir les périphériques en une liste utilisable par Zenity
formatted_devices=$(echo "$capture_devices" | awk '{print NR ": " $0}' | sed 's/ /+/g')
selected=$(zenity --entry --title="Sélectionnez un périphérique" \
    --text="Choisissez un périphérique de capture :" \
    --entry-text=$(echo "$formatted_devices") --width=600)

if [ $? -ne 0 ] || [ -z "$selected" ]; then
    zenity --info --text="Annulation par l'utilisateur." --width=300
    exit 1
fi

# Vérification et extraction du périphérique sélectionné
if ! [[ $(echo "$selected" | tr '_' ' ' | awk -F':+' '{print $1}') =~ ^[0-9]+$ ]]; then
    zenity --error --text="Le périphérique sélectionné n'est pas valide." --width=300
    exit 1
fi

# Extraire le périphérique sélectionné
selected_device=$(echo "$selected" | tr '+' ' ' | awk -F': ' '{print $2}')

# Vérification que le périphérique sélectionné existe
if ! echo "$capture_devices" | grep -F "$selected_device"; then
    zenity --error --text="Le périphérique sélectionné n'est pas valide." --width=300
    exit 1
fi

# Vérifier que le périphérique a bien été récupéré
if [ -z "$selected_device" ]; then
    zenity --error --text="Le périphérique sélectionné n'existe pas." --width=300
    exit 1
fi

# Afficher le périphérique sélectionné
zenity --info --text="Vous avez sélectionné : $selected_device" --width=300

# Définition des ports
INPUT_PORT="$selected_device"
GX_HEAD_AMP_INPUT=$(normalize_port_name "gx_head_amp:in_0")
GX_HEAD_FX_OUTPUT_L=$(normalize_port_name "gx_head_fx:out_0")
GX_HEAD_FX_OUTPUT_R=$(normalize_port_name "gx_head_fx:out_1")
ARDOUR_MASTER_OUTPUT_L=$(normalize_port_name "ardour:Master/audio_out 1")
ARDOUR_MASTER_OUTPUT_R=$(normalize_port_name "ardour:Master/audio_out 2")
ARDOUR_GX_TRACK_INPUT_L=$(normalize_port_name "ardour:Master/audio_in 1")
ARDOUR_GX_TRACK_INPUT_R=$(normalize_port_name "ardour:Master/audio_in 2")

# Vérification et lancement de Guitarix
if ! pgrep -x "guitarix" > /dev/null; then
    pw-jack guitarix &
    sleep 2
fi
if ! pgrep -x "guitarix" > /dev/null; then
    zenity --error --text="Erreur : Guitarix n'a pas pu être lancé." --width=300
    exit 1
fi

# Trouver dynamiquement les ports JACK associés au périphérique de sortie
if detect_jack_ports "$DESCRIPTIVE_NAME:playback_FL" "$DESCRIPTIVE_NAME:playback_FR"; then
    echo "Ports JACK détectés avec succès (méthode 1)."
elif detect_jack_ports "$DESCRIPTIVE_NAME:playback_AUX0" "$DESCRIPTIVE_NAME:playback_AUX1"; then
    echo "Ports JACK détectés avec succès (méthode 2)."
else
    echo "Erreur : Impossible de trouver les ports JACK pour le périphérique de sortie."
    exit 1
fi

# Continuer avec le reste du script
echo "Ports JACK trouvés avec succès. Continuation du script..."

# Attendre un instant pour s'assurer que les ports sont chargés
MAX_WAIT=10  # Attente maximale en secondes
for i in $(seq 1 $MAX_WAIT); do
    if pw-jack jack_lsp | grep -q $(denormalize_port_name "$GX_HEAD_AMP_INPUT"); then
        break
    fi
    echo "Attente des ports de Guitarix... ($i/$MAX_WAIT)"
    sleep 1
done

# Vérifier la disponibilité des ports Guitarix
if ! pw-jack jack_lsp | grep -q $(denormalize_port_name "$GX_HEAD_AMP_INPUT"); then
    zenity --error --text="Erreur : L'entrée de Guitarix ($(denormalize_port_name $GX_HEAD_AMP_INPUT)) n'est pas disponible. Vérifiez que Guitarix est correctement lancé." --width=300
    exit 1
fi

disconnect_all_ports

# Vérifier et connecter INPUT_PORT -> GX_HEAD_AMP_INPUT
echo "Tentative de connexion : $INPUT_PORT -> $(denormalize_port_name $GX_HEAD_AMP_INPUT)"
if ! pw-jack jack_connect "$INPUT_PORT" $(denormalize_port_name "$GX_HEAD_AMP_INPUT"); then
    zenity --error --text="Erreur : Impossible de connecter la guitare ($INPUT_PORT) à l'entrée de Guitarix ($(denormalize_port_name $GX_HEAD_AMP_INPUT))." --width=300
    exit 1
else
    echo "Connexion réussie : $(denormalize_port_name $INPUT_PORT) -> $(denormalize_port_name $GX_HEAD_AMP_INPUT)"
fi

# Sélection de la méthode de connexion
CHOICE=$(zenity --entry --title="Sélectionnez un périphérique" \
    --text="Choisissez la méthode de connexion :" \
    --entry-text="Connexion directe via Guitarix" "Passer par Ardour" --width=600)



if [ -z "$OUTPUT_PORT_L" ] || [ -z "$OUTPUT_PORT_R" ]; then
    zenity --error --text="Erreur : Les ports de sortie ne sont pas définis correctement. Vérifiez votre configuration." --width=400
    exit 1
fi

OUTPUT_PORT_L=$(normalize_port_name "$OUTPUT_PORT_L")
OUTPUT_PORT_R=$(normalize_port_name "$OUTPUT_PORT_R")

if [ "$CHOICE" == "Connexion directe via Guitarix" ]; then

    ports=( \
        "$GX_HEAD_FX_OUTPUT_L:$OUTPUT_PORT_L" \
        "$GX_HEAD_FX_OUTPUT_R:$OUTPUT_PORT_R" \
    )
elif [ "$CHOICE" == "Passer par Ardour" ]; then
    # Lancer Ardour avec PipeWire
    pw-jack /usr/bin/ardour &
    zenity --info --text="Ardour a été lancé. Veuillez :
1. Créer ou ouvrir un projet.
2. Ajouter au moins une piste audio.\n\nAppuyez sur OK lorsque vous êtes prêt à continuer." --width=400

    # Attendre que l'utilisateur configure Ardour
    MAX_WAIT=300  # 5 minutes maximum
    for i in $(seq 1 $MAX_WAIT); do
        ardour_ports=$(pw-jack jack_lsp | grep -E "ardour:.*audio_in")
        if [ -n "$ardour_ports" ]; then
            echo "Ports d'entrée audio d'Ardour détectés après $i secondes."
            break
        fi
        if [ "$i" -eq "$MAX_WAIT" ]; then
            zenity --error --text="Erreur : Aucun port d'entrée audio détecté dans Ardour après 5 minutes. Assurez-vous qu'un projet est ouvert et contient au moins une piste audio." --width=400
            exit 1
        fi
        echo "Attente des ports d'Ardour... ($i/$MAX_WAIT)"
        sleep 1
    done

    # Normaliser les noms de ports pour Zenity
    declare -A port_mapping
    normalized_ports=""
    while read -r port; do
        normalized_name=$(echo "$port" | sed 's/[ /]/_/g')  # Remplace espaces et / par _
        port_mapping["$normalized_name"]="$port"           # Map normalisé -> original
        normalized_ports+="$normalized_name "
    done <<< "$ardour_ports"

    # Afficher les ports disponibles dans un menu Zenity
    selected_normalized=$(zenity --list --title="Sélectionnez une entrée audio" \
        --text="Voici les pistes audio disponibles dans Ardour. Sélectionnez celle à associer à la guitare." \
        --column="Port Audio" $normalized_ports --width=500 --height=300)

    if [ -z "$selected_normalized" ]; then
        zenity --error --text="Aucune entrée audio sélectionnée. Veuillez choisir une entrée valide." --width=300
        exit 1
    fi

    # Récupérer le port original correspondant au nom normalisé
    selected_port="${port_mapping[$selected_normalized]}"
    zenity --info --text="Vous avez sélectionné : $selected_port" --width=300
    normalized_selected_port=$(normalize_port_name "$selected_port")

    # Connexions :
    # - Sortie de Guitarix vers l'entrée audio sélectionnée
    # - Sorties Master d'Ardour vers les sorties système

    echo "Connexion de Guitarix à Ardour :"
    echo "Connexion des sorties Master d'Ardour au système :"
    ports=( \
        "$GX_HEAD_FX_OUTPUT_L:$normalized_selected_port" \
        "$ARDOUR_MASTER_OUTPUT_L:$OUTPUT_PORT_L" \
        "$ARDOUR_MASTER_OUTPUT_R:$OUTPUT_PORT_R" \
    )

    zenity --info --text="Les connexions ont été établies avec succès !" --width=300
fi

# Établir les connexions
for pair in "${ports[@]}"; do
    src="${pair%%:*}"
    dst="${pair##*:}"
    normalized_src=$(denormalize_port_name "$src")
    normalized_dst=$(denormalize_port_name "$dst")
    connect_ports "$normalized_src" "$normalized_dst"
done

zenity --info --text="Les connexions ont été établies avec succès !" --width=300
