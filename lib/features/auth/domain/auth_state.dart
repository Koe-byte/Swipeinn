import 'user_model.dart';

/// Where the person is in the sign-in funnel.
enum AuthStatus {
  /// Reading the persisted Supabase session on cold start.
  restoring,

  /// No Supabase session.
  signedOut,

  /// Signed in, but the email address has not been confirmed yet.
  unverified,

  /// Email confirmed, profile loaded, but the two-step preferences are missing.
  needsOnboarding,

  /// Full access.
  ready,

  /// The backend could not be reached or configured. The UI shows a retry.
  failure,
}

/// The slice of Supabase Auth identity the app needs. Kept separate from
/// [UserModel] because it exists even before the profile row does.
class AuthIdentity {
  final String uid;
  final String email;
  final String displayName;
  final bool isEmailVerified;

  const AuthIdentity({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isEmailVerified,
  });
}

/// Immutable snapshot consumed by the auth gate.
class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? email;
  final String? errorMessage;

  /// Mirrors `email_confirmed_at` on the Supabase user. Displaying it is the
  /// only job: the gate already routes unverified sessions to the verify
  /// screen, so the profile only ever sees this when it is true.
  final bool isEmailVerified;

  /// Non-error notice, such as "verification email sent".
  final String? infoMessage;

  /// True while a sign-in, sign-up, reset, or profile write is in flight.
  /// Kept separate from [status] so screens can show a spinner without
  /// unmounting themselves.
  final bool isSubmitting;

  const AuthState({
    this.status = AuthStatus.restoring,
    this.user,
    this.email,
    this.isEmailVerified = false,
    this.errorMessage,
    this.infoMessage,
    this.isSubmitting = false,
  });

  bool get isSignedIn =>
      status == AuthStatus.unverified ||
      status == AuthStatus.needsOnboarding ||
      status == AuthStatus.ready;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? email,
    bool? isEmailVerified,
    String? errorMessage,
    String? infoMessage,
    bool clearError = false,
    bool clearInfo = false,
    bool clearUser = false,
    bool? isSubmitting,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      email: email ?? this.email,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}
