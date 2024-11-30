#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

# Nettoyage des processus en cas d'erreur ou d'interruption
#trap "pkill -f guitarix || true" EXIT

# TODO: Ajouter une fonction pour détecter les périphériques de sortie audio
#       - Cette fonction devra lister les périphériques disponibles avec pw-jack et permettre à l'utilisateur de choisir.

# Fonction pour récupérer les périphériques de capture
get_capture_devices() {
    pw-jack jack_lsp | grep -E "capture" | grep -v "Midi" | sed 's/^[ \t]*//'
}

# Récupérer les périphériques disponibles
capture_devices=$(get_capture_devices)

# Vérifier qu'il y a des périphériques disponibles
if [ -z "$capture_devices" ]; then
    zenity --error --text="Aucun périphérique de capture détecté !" --width=300
    exit 1
fi

# Convertir les périphériques en une liste utilisable par Zenity
formatted_devices=$(echo "$capture_devices" | awk '{print NR ": " $0}' | sed 's/ /+/g')

# Afficher le menu pour sélectionner un périphérique
selected=$(zenity --entry --title="Sélectionnez un périphérique" \
    --text="Choisissez un périphérique de capture dans le menu ci-dessous :" \
    --width=600\
    --entry-text=$(echo "$formatted_devices"))

# TODO: Ajouter une vérification stricte des entrées utilisateur pour éviter les erreurs inattendues.

# Vérifier si l'utilisateur a annulé
if [ $? -ne 0 ]; then
    zenity --info --text="Annulation par l'utilisateur." --width=300
    exit 1
fi

# Valider la sélection pour s'assurer qu'elle est correcte
if ! [[ $(echo "$selected" | tr '_' ' ' | awk -F':+' '{print $1}') =~ ^[0-9]+$ ]]; then
    zenity --error --text="Entrée invalide. Veuillez entrer un numéro valide." --width=300
    exit 1
fi

# TODO: Traiter correctement les caractères spéciaux dans les noms de périphériques pour éviter les problèmes lors des connexions.

# Extraire le périphérique sélectionné
selected_device=$(echo "$selected" | tr '+' ' ' | awk -F': ' '{print $2}')

# Vérifier que le périphérique a bien été récupéré
if [ -z "$selected_device" ]; then
    zenity --error --text="Le périphérique sélectionné n'existe pas." --width=300
    exit 1
fi

# Afficher le périphérique sélectionné
zenity --info --text="Vous avez sélectionné : $selected_device" --width=300

# TODO: Ajouter des profils enregistrés pour simplifier la configuration (ex. casque, haut-parleurs, etc.).

# Nom des ports (entrée guitare et sortie Guitarix)
INPUT_PORT="$selected_device"
GX_HEAD_AMP_INPUT="gx_head_amp:in_0"
GX_HEAD_FX_OUTPUT_L="gx_head_fx:out_0"
GX_HEAD_FX_OUTPUT_R="gx_head_fx:out_1"

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

# Fonction pour déconnecter toutes les connexions existantes
disconnect_all_ports() {
    echo "Déconnexion de toutes les connexions existantes..."
    # Déconnecter toutes les connexions Guitarix -> périphériques
    pw-jack jack_lsp | grep -E "capture|playback|output" | while read -r PORT; do
        CONNECTED_PORTS=$(pw-jack jack_lsp -c "$PORT" | awk '{print $1}' | tr -d '\r')
        for CONNECTED_PORT in $CONNECTED_PORTS; do
            if pw-jack jack_disconnect "$PORT" "$CONNECTED_PORT" 2>/dev/null; then
                echo "Déconnecté : $PORT -> $CONNECTED_PORT"
            fi
        done
    done
    echo "Toutes les connexions précédentes ont été déconnectées."
}

# Vérifier si Guitarix est déjà en cours d'exécution
if pgrep -x "guitarix" > /dev/null; then
    echo "Guitarix est déjà en cours d'exécution. Aucun besoin de le relancer."
else
    echo "Lancement de Guitarix..."
    pw-jack guitarix &
    sleep 2  # Attendre un instant pour s'assurer que les ports sont chargés
fi

# TODO: Ajouter une vérification pour s'assurer que Guitarix s'est lancé correctement.

# Détecter le périphérique de sortie par défaut
DEFAULT_SINK=$(pactl get-default-sink)
echo "Nom interne du périphérique par défaut : $DEFAULT_SINK"

# TODO: Ajouter une option pour sélectionner manuellement le périphérique de sortie si nécessaire.

# Récupérer le nom descriptif du périphérique (nettoyé)
DESCRIPTIVE_NAME=$(pactl list sinks | grep -A 5 -E "$DEFAULT_SINK" | grep -E "Description*" | cut -d ":" -f 2 | sed 's/^ *//')

# Déconnecter les précédentes sorties
disconnect_all_ports

# Stocker le périphérique actuel pour la prochaine exécution
echo "$DESCRIPTIVE_NAME" > /tmp/previous_device_name

# Vérifier que la description est trouvée
if [ -z "$DESCRIPTIVE_NAME" ]; then
    echo "Erreur : La description du périphérique audio n'a pas pu être trouvée."
    exit 1
fi
echo "Nom descriptif du périphérique : $DESCRIPTIVE_NAME"

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
    if pw-jack jack_lsp | grep -q "gx_head_amp"; then
        break
    fi
    echo "Attente des ports de Guitarix..."
    sleep 1
done

# Vérifier que les ports Guitarix sont disponibles
if ! pw-jack jack_lsp | grep -q "gx_head_amp"; then
    echo "Erreur : Les ports de Guitarix ne sont pas disponibles."
    exit 1
fi

# Connecter les ports JACK
echo "Connexion des ports JACK..."

# Vérifier et connecter INPUT_PORT -> GX_HEAD_AMP_INPUT
if ! pw-jack jack_lsp -c "$INPUT_PORT" | grep -q "$GX_HEAD_AMP_INPUT"; then
    if pw-jack jack_connect "$INPUT_PORT" "$GX_HEAD_AMP_INPUT"; then
        echo "Connexion réussie : '$INPUT_PORT' -> '$GX_HEAD_AMP_INPUT'"
    else
        echo "Erreur lors de la connexion : '$INPUT_PORT' -> '$GX_HEAD_AMP_INPUT'"
    fi
else
    echo "Connexion déjà existante : '$INPUT_PORT' -> '$GX_HEAD_AMP_INPUT'"
fi

# Vérifier et connecter GX_HEAD_FX_OUTPUT_L -> OUTPUT_PORT_L
if ! pw-jack jack_lsp -c "$GX_HEAD_FX_OUTPUT_L" | grep -q "$OUTPUT_PORT_L"; then
    if pw-jack jack_connect "$GX_HEAD_FX_OUTPUT_L" "$OUTPUT_PORT_L"; then
        echo "Connexion réussie : '$GX_HEAD_FX_OUTPUT_L' -> '$OUTPUT_PORT_L'"
    else
        echo "Erreur lors de la connexion : '$GX_HEAD_FX_OUTPUT_L' -> '$OUTPUT_PORT_L'"
    fi
else
    echo "Connexion déjà existante : '$GX_HEAD_FX_OUTPUT_L' -> '$OUTPUT_PORT_L'"
fi

# Vérifier et connecter GX_HEAD_FX_OUTPUT_R -> OUTPUT_PORT_R
if ! pw-jack jack_lsp -c "$GX_HEAD_FX_OUTPUT_R" | grep -q "$OUTPUT_PORT_R"; then
    if pw-jack jack_connect "$GX_HEAD_FX_OUTPUT_R" "$OUTPUT_PORT_R"; then
        echo "Connexion réussie : '$GX_HEAD_FX_OUTPUT_R' -> '$OUTPUT_PORT_R'"
    else
        echo "Erreur lors de la connexion : '$GX_HEAD_FX_OUTPUT_R' -> '$OUTPUT_PORT_R'"
    fi
else
    echo "Connexion déjà existante : '$GX_HEAD_FX_OUTPUT_R' -> '$OUTPUT_PORT_R'"
fi

echo "Configuration terminée. Guitarix est prêt à être utilisé."
