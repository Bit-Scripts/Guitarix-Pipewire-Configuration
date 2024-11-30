#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

# Nettoyage des processus en cas d'erreur ou d'interruption
#trap "pkill -f guitarix || true" EXIT

# Nom des ports (entrée guitare et sortie Guitarix)
INPUT_PORT="PCM2900C Audio CODEC Analog Stereo:capture_FL"
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

# Fonction pour déconnecter toutes les connexions existantes pour un périphérique
disconnect_all_ports() {
    echo "Déconnexion de toutes les connexions existantes..."

    # Étape 1 : Récupérer les ports de capture audio (exclure MIDI)
    mapfile -t CAPTURE_PORTS < <(pw-jack jack_lsp | grep -E "capture" | grep -v "Midi" | sed 's/^[ \t]*//')

    # Étape 2 : Déconnecter les captures de leurs connexions
    for CAPTURE_PORT in "${CAPTURE_PORTS[@]}"; do
        CONNECTED_OUTPUTS=$(pw-jack jack_lsp -c "$CAPTURE_PORT" | grep -E "playback|output" | awk '{print $1}' | tr -d '\r')
        for OUTPUT_PORT in $CONNECTED_OUTPUTS; do
            if pw-jack jack_disconnect "$CAPTURE_PORT" "$OUTPUT_PORT"; then
                echo "Déconnexion réussie : '$CAPTURE_PORT' -> '$OUTPUT_PORT'"
            else
                echo "Erreur lors de la déconnexion : '$CAPTURE_PORT' -> '$OUTPUT_PORT'"
            fi
        done
    done

    # Étape 3 : Récupérer les ports de sortie audio (exclure MIDI)
    mapfile -t OUTPUT_PORTS < <(pw-jack jack_lsp | grep -E "playback|output" | grep -v "Midi" | sed 's/^[ \t]*//')

    # Étape 4 : Déconnecter les sorties de leurs connexions
    for OUTPUT_PORT in "${OUTPUT_PORTS[@]}"; do
        CONNECTED_INPUTS=$(pw-jack jack_lsp -c "$OUTPUT_PORT" | grep -E "capture|input" | grep -v "Midi" | awk '{print $1}' | tr -d '\r')
        for INPUT_PORT in $CONNECTED_INPUTS; do
            if pw-jack jack_disconnect "$INPUT_PORT" "$OUTPUT_PORT"; then
                echo "Déconnexion réussie : '$INPUT_PORT' -> '$OUTPUT_PORT'"
            else
                echo "Erreur lors de la déconnexion : '$INPUT_PORT' -> '$OUTPUT_PORT'"
            fi
        done
    done

    echo "Toutes les connexions précédentes ont été déconnectées."
}

# Détecter le périphérique de sortie par défaut
DEFAULT_SINK=$(pactl get-default-sink)
echo "Nom interne du périphérique par défaut : $DEFAULT_SINK"

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

# Lancer Guitarix avec PipeWire-JACK
pw-jack guitarix &

# Attendre un instant pour s'assurer que les ports sont chargés
sleep 2
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
pw-jack jack_connect "$INPUT_PORT" "$GX_HEAD_AMP_INPUT"
pw-jack jack_connect "$GX_HEAD_FX_OUTPUT_L" "$OUTPUT_PORT_L"
pw-jack jack_connect "$GX_HEAD_FX_OUTPUT_R" "$OUTPUT_PORT_R"

echo "Configuration terminée. Guitarix est prêt à être utilisé."
