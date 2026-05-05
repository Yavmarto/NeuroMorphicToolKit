import re

with open('/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/app_theme.dart', 'r') as f:
    text = f.read()

# Replace _neurocnlExtension
old_neurocnl = """      synKeyword: NmtkNeurocnlTokens.synKeyword,
      synSubject: NmtkNeurocnlTokens.synSubject,
      synNumber: NmtkNeurocnlTokens.synNumber,
      synComment: NmtkNeurocnlTokens.synComment,
      synString: NmtkNeurocnlTokens.synString,
      nodeEnsemble: NmtkNeurocnlTokens.nodeEnsemble,
      nodeMotor: NmtkNeurocnlTokens.nodeMotor,
      nodeInterneuron: NmtkNeurocnlTokens.nodeInterneuron,
      nodeInput: NmtkNeurocnlTokens.nodeInput,
      nodeErrorInput: NmtkNeurocnlTokens.nodeError,
      edgeExcitatory: NmtkNeurocnlTokens.edgeExcitatory,
      edgeInhibitory: NmtkNeurocnlTokens.edgeInhibitory,
      edgePlastic: NmtkNeurocnlTokens.edgePlastic,"""

new_neurocnl = """      synKeyword: isDark ? NmtkNeurocnlTokens.synKeyword : const Color(0xFF1D4ED8), // Darken for light mode
      synSubject: isDark ? NmtkNeurocnlTokens.synSubject : const Color(0xFF0284C7),
      synNumber: isDark ? NmtkNeurocnlTokens.synNumber : const Color(0xFFD97706),
      synComment: isDark ? NmtkNeurocnlTokens.synComment : const Color(0xFF4B5563),
      synString: isDark ? NmtkNeurocnlTokens.synString : const Color(0xFF059669),
      nodeEnsemble: isDark ? NmtkNeurocnlTokens.nodeEnsemble : const Color(0xFF2563EB),
      nodeMotor: isDark ? NmtkNeurocnlTokens.nodeMotor : const Color(0xFFD97706),
      nodeInterneuron: isDark ? NmtkNeurocnlTokens.nodeInterneuron : const Color(0xFF0D9488),
      nodeInput: isDark ? NmtkNeurocnlTokens.nodeInput : const Color(0xFF16A34A),
      nodeErrorInput: isDark ? NmtkNeurocnlTokens.nodeError : const Color(0xFFDC2626),
      edgeExcitatory: isDark ? NmtkNeurocnlTokens.edgeExcitatory : const Color(0xFF2563EB),
      edgeInhibitory: isDark ? NmtkNeurocnlTokens.edgeInhibitory : const Color(0xFFDC2626),
      edgePlastic: isDark ? NmtkNeurocnlTokens.edgePlastic : const Color(0xFFD97706),"""

text = text.replace(old_neurocnl, new_neurocnl)

# In _suiteExtension we also need to override the defaults. 
# It currently is defined as:
old_suite = """      glassmorphismColor: isDark
          ? NmtkDesignTokens.backgroundDark.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.7),
      variant: variant,
    );"""

new_suite = """      glassmorphismColor: isDark
          ? NmtkDesignTokens.backgroundDark.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.7),
      synKeyword: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      synSubject: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
      synNumber: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
      synComment: isDark ? const Color(0xFF6B7280) : const Color(0xFF4B5563),
      synString: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
      nodeEnsemble: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
      nodeMotor: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      nodeInterneuron: isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488),
      nodeInput: isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A),
      nodeErrorInput: isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626),
      edgeExcitatory: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
      edgeInhibitory: isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626),
      edgePlastic: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      variant: variant,
    );"""

text = text.replace(old_suite, new_suite)

with open('/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/lib/app_theme.dart', 'w') as f:
    f.write(text)

print("Updated app_theme.dart")
