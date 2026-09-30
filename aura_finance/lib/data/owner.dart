import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'remote/neon.dart';

/// Stempel kepemilikan untuk baris baru: rumah tangga aktif & pengguna yang login.
/// Keduanya boleh null saat mode lokal; akan diisi ketika rumah tangga dibuat.
({String? householdId, String? userId}) ownerStamp(WidgetRef ref) => (
      householdId: ref.read(householdIdProvider),
      userId: Neon.auth.currentUser?.id,
    );
