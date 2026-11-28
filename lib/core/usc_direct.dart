import 'backend_service.dart';
import 'usc.dart';

/// Live USC lookup straight from the DISCOM portals, with no backend server.
/// Uses the direct fetchers in [BackendService]. Never invents data.
class DirectUscSource implements UscSource {
  const DirectUscSource();

  /// Only TGSPDCL shows a security code. The other DISCOMs don't.
  @override
  bool needsCaptcha(UscDiscom discom) => discom.code == 'TGSPDCL';

  @override
  Future<UscRecord> fetch({required String usc, required UscDiscom discom, String? captcha, String? captchaId}) async {
    final res = await BackendService.fetchUscBill(
      rawBaseUrl: '',
      usc: usc,
      stateId: discom.region.label.toLowerCase(),
      discomId: discom.code,
      category: 'residential',
      captchaId: captchaId,
      captchaAnswer: captcha,
    );

    final challenge = res.captchaChallenge;
    if (res.needsCaptcha && challenge != null) {
      throw UscCaptchaRequired(
        res.message ?? challenge.hint,
        captchaId: challenge.captchaId,
        image: challenge.imageDataUri,
      );
    }
    if (res.needsMobile) {
      throw UscException(res.message ?? '${discom.code} needs the mobile number linked to this USC. Not supported on this screen yet.');
    }
    if (!res.ok && res.history.isEmpty && res.avgMonthlyUnits <= 0 && res.avgMonthlyBill <= 0) {
      throw UscException(res.error ?? res.message ?? 'Could not fetch bill for USC $usc.');
    }

    final months = <UscMonth>[
      for (final h in res.history)
        UscMonth(month: h.month, units: h.units, bill: h.amount, onPortal: true),
    ];
    if (months.isEmpty) {
      months.add(UscMonth(
        month: res.billDate.isNotEmpty ? res.billDate : 'Latest',
        units: res.avgMonthlyUnits,
        bill: res.avgMonthlyBill,
        onPortal: true,
        present: true,
      ));
    }

    return UscRecord(
      usc: res.usc.isNotEmpty ? res.usc : usc,
      discom: discom,
      consumerName: res.consumerName,
      address: res.address,
      fetchedAt: DateTime.now(),
      months: months,
    );
  }
}
