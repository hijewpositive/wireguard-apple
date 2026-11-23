// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import UIKit
import os.log

class ErrorPresenter: ErrorPresenterProtocol {
    static func showErrorAlert(title: String, message: String, from sourceVC: AnyObject?, onPresented: (() -> Void)?, onDismissal: (() -> Void)?) {
        guard let sourceVC = sourceVC as? UIViewController else { return }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            alert?.dismiss(animated: true, completion: onDismissal)
        }
        alert.addAction(okAction)

        sourceVC.present(alert, animated: true, completion: onPresented)
    }
}
